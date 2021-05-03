[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$AdminSecret,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode1NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode2NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode2PrivateIP2

)

Import-Module FailoverClusters

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

# Getting Password from Secrets Manager for AD Admin User
$AdminUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $AdminSecret).SecretString
$ClusterAdminUser = $DomainNetBIOSName + '\' + $AdminUser.UserName
# Creating Credential Object for Administrator
$Credentials = (New-Object PSCredential($ClusterAdminUser,(ConvertTo-SecureString $AdminUser.Password -AsPlainText -Force)))

$WSFCNode2SubnetMask = (Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode2NetBIOSName))
                 
if ( !(Get-ClusterResource -Name NewIP) ) {
  Add-ClusterResource –Name NewIP –ResourceType "IP Address" –Group "Cluster Group"
}                  
Get-ClusterResource -Name NewIP | Set-ClusterParameter -Multiple @{"Address"=$WSFCNode2PrivateIP2;"SubnetMask"=$WSFCNode2SubnetMask} 
Set-ClusterResourceDependency -Resource "Cluster Name" -Dependency "[Cluster IP Address] or [NewIP]"
Get-ClusterResource -Name NewIP | Set-ClusterOwnerNode -Owners $WSFCNode2NetBIOSName
Get-ClusterResource -Name "Cluster IP Address" | Set-ClusterOwnerNode -Owners $WSFCNode1NetBIOSName
Start-ClusterResource -Name NewIP -ErrorAction SilentlyContinue
