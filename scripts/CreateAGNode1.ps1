[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainDNSName,

    [Parameter(Mandatory=$true)]
    [string]$AdminSecret,

    [Parameter(Mandatory=$true)]
    [string]$SQLSecret,

    [Parameter(Mandatory=$true)]
    [string]$ClusterName,

    [Parameter(Mandatory=$true)]
    [string]$AvailabiltyGroupName,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode1NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode2NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$AGListener1PrivateIP1,

    [Parameter(Mandatory=$true)]
    [string]$AGListener1PrivateIP2,

    [Parameter(Mandatory=$false)]
    [string]$WSFCNode3NetBIOSName,

    [Parameter(Mandatory=$false)]
    [string]$AGListener1PrivateIP3,

    [Parameter(Mandatory=$false)]
    [string] $ManagedAD

)

Function Get-Domain {
	
	#Retrieve the Fully Qualified Domain Name if one is not supplied
	# division.domain.root
	if ($DomainDNSName -eq "") {
		[String]$DomainDNSName = [System.DirectoryServices.ActiveDirectory.Domain]::getcurrentdomain()
	}

	# Create an Array 'Item' for each item in between the '.' characters
	$FQDNArray = $DomainDNSName.split(".")
	
	# Add A Separator of ','
	$Separator = ","

	# For Each Item in the Array
	# for (CreateVar; Condition; RepeatAction)
	# for ($x is now equal to 0; while $x is less than total array length; add 1 to X
	for ($x = 0; $x -lt $FQDNArray.Length ; $x++)
		{ 

		#If it's the last item in the array don't append a ','
		if ($x -eq ($FQDNArray.Length - 1)) { $Separator = "" }
		
		# Append to $DN DC= plus the array item with a separator after
		[string]$DN += "DC=" + $FQDNArray[$x] + $Separator
		
		# continue to next item in the array
		}
	
	#return the Distinguished Name
	return $DN
}

Function Convert-CidrtoSubnetMask { 
    Param ( 
        [String] $SubnetMaskCidr
    ) 

    Function Convert-Int64ToIpAddress() { 
      Param 
      ( 
          [int64] 
          $Int64 
      ) 
   
      # Return 
      '{0}.{1}.{2}.{3}' -f ([math]::Truncate($Int64 / 16777216)).ToString(), 
          ([math]::Truncate(($Int64 % 16777216) / 65536)).ToString(), 
          ([math]::Truncate(($Int64 % 65536)/256)).ToString(), 
          ([math]::Truncate($Int64 % 256)).ToString() 
    } 
 
    # Return
    Convert-Int64ToIpAddress -Int64 ([convert]::ToInt64(('1' * $SubnetMaskCidr + '0' * (32 - $SubnetMaskCidr)), 2)) 
}

Function Get-CIDR {
    Param ( 
        [String] $Target
    ) 
    Invoke-Command -ComputerName $Target -Credential $Credentials -Scriptblock {(Get-NetIPConfiguration).IPv4Address.PrefixLength[0]}
}

# Getting the DSC Cert Encryption Thumbprint to Secure the MOF File
$DscCertThumbprint = (get-childitem -path cert:\LocalMachine\My | where { $_.subject -eq "CN=AWSQSDscEncryptCert" }).Thumbprint
# Getting Password from Secrets Manager for AD Admin User
$AdminUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $AdminSecret).SecretString
$SQLUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $SQLSecret).SecretString
$ClusterAdminUser = $DomainNetBIOSName + '\' + $AdminUser.UserName
$SQLAdminUser = $DomainNetBIOSName + '\' + $SQLUser.UserName
# Creating Credential Object for Administrator
$Credentials = (New-Object PSCredential($ClusterAdminUser,(ConvertTo-SecureString $AdminUser.Password -AsPlainText -Force)))
$SQLCredentials = (New-Object PSCredential($SQLAdminUser,(ConvertTo-SecureString $SQLUser.Password -AsPlainText -Force)))
# Getting the Name Tag of the Instance
$NameTag = (Get-EC2Tag -Filter @{ Name="resource-id";Values=(Invoke-RestMethod -Method Get -Uri http://169.254.169.254/latest/meta-data/instance-id)}| Where-Object { $_.Key -eq "Name" })
$NetBIOSName = $NameTag.Value

$IPADDR = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP1 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode1NetBIOSName))
$IPADDR2 = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP2 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode2NetBIOSName))
if ($AGListener1PrivateIP3) {
    $IPADDR3 = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP3 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode3NetBIOSName))  
}

if ($ManagedAD -eq 'Yes'){
    $DN = Get-Domain
    $IdentityReference = $DomainNetBIOSName + "\" + $ClusterName + "$"
    $OUPath = 'CN=Computers,' + $DN
}



$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName     = '*'
            CertificateFile = "C:\AWSQuickstart\publickeys\AWSQSDscPublicKey.cer"
            Thumbprint = $DscCertThumbprint
            PSDscAllowDomainUser = $true
        },
        @{
            NodeName = $NetBIOSName
        }
    )
}

Configuration AddAG {
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential]$SQLCredentials,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credentials
    )

    Import-Module -Name PSDesiredStateConfiguration
    Import-Module -Name ActiveDirectoryDsc
    Import-Module -Name SqlServerDsc
    
    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module ActiveDirectoryDsc
    Import-DscResource -Module SqlServerDsc

    Node $AllNodes.NodeName {
        SqlMaxDop 'SQLServerMaxDopAuto' {
            Ensure                  = 'Present'
            DynamicAlloc            = $true
            ServerName              = $NetBIOSName
            InstanceName            = 'MSSQLSERVER'
            PsDscRunAsCredential    = $SQLCredentials
            ProcessOnlyOnActiveNode = $true
        }

        SqlConfiguration 'SQLConfigPriorityBoost'{
            ServerName     = $NetBIOSName
            InstanceName   = 'MSSQLSERVER'
            OptionName     = 'cost threshold for parallelism'
            OptionValue    = 20
        }

        SqlAlwaysOnService 'EnableAlwaysOn' {
            Ensure               = 'Present'
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlLogin 'AddNTServiceClusSvc' {
            Ensure               = 'Present'
            Name                 = 'NT SERVICE\ClusSvc'
            LoginType            = 'WindowsUser'
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlPermission 'AddNTServiceClusSvcPermissions' {
            DependsOn            = '[SqlLogin]AddNTServiceClusSvc'
            Ensure               = 'Present'
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            Principal            = 'NT SERVICE\ClusSvc'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlEndpoint 'HADREndpoint' {
            EndPointName         = 'HADR'
            EndpointType         = 'DatabaseMirroring'
            Ensure               = 'Present'
            Port                 = 5022
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }
        
        if ($ManagedAD -eq 'Yes'){
            WindowsFeature RSAT-ADDS-Tools {
                Name = 'RSAT-ADDS-Tools'
                Ensure = 'Present'
            }

            ADObjectPermissionEntry 'ADObjectPermissionEntry' {
                Ensure                             = 'Present'
                Path                               = $OUPath
                IdentityReference                  = $IdentityReference
                ActiveDirectoryRights              = 'GenericAll'
                AccessControlType                  = 'Allow'
                ObjectType                         = '00000000-0000-0000-0000-000000000000'
                ActiveDirectorySecurityInheritance = 'All'
                InheritedObjectType                = '00000000-0000-0000-0000-000000000000'
                PsDscRunAsCredential               = $Credentials
            }
        }

        SqlAG 'AddSQLAG1' {
            Ensure               = 'Present'
            Name                 = $AvailabiltyGroupName
            InstanceName         = 'MSSQLSERVER'
            ServerName           = $NetBIOSName
            AvailabilityMode     = 'SynchronousCommit'
            FailoverMode         = 'Automatic'
            DependsOn = '[SqlAlwaysOnService]EnableAlwaysOn', '[SqlEndpoint]HADREndpoint', '[SqlPermission]AddNTServiceClusSvcPermissions'
            PsDscRunAsCredential = $SQLCredentials
        }

        if ($AGListener1PrivateIP3) {
            SqlAGListener 'AGListener1' {
                Ensure               = 'Present'
                ServerName           = $NetBIOSName
                InstanceName         = 'MSSQLSERVER'
                AvailabilityGroup    = $AvailabiltyGroupName
                Name                 = $AvailabiltyGroupName
                IpAddress            = $IPADDR,$IPADDR2,$IPADDR3
                Port                 = 5301
                DependsOn            = '[SqlAG]AddSQLAG1'
                PsDscRunAsCredential = $SQLCredentials
            }
        } else {
            SqlAGListener 'AGListener1' {
                Ensure               = 'Present'
                ServerName           = $NetBIOSName
                InstanceName         = 'MSSQLSERVER'
                AvailabilityGroup    = $AvailabiltyGroupName
                Name                 = $AvailabiltyGroupName
                IpAddress            = $IPADDR,$IPADDR2
                Port                 = 5301
                DependsOn            = '[SqlAG]AddSQLAG1'
                PsDscRunAsCredential = $SQLCredentials
            }
        }
    }
}

AddAG -OutputPath 'C:\AWSQuickstart\AddAG' -Credentials $Credentials -SQLCredentials $SQLCredentials -ConfigurationData $ConfigurationData