[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainDnsName,

    [Parameter(Mandatory=$true)]
    [string]$AdminSecret,

    [Parameter(Mandatory=$true)]
    [string]$SQLServerVersion,

    [Parameter(Mandatory=$true)]
    [string]$SQLSecret

)

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

# Extract Install from Downloaded ISO
New-Item -Path C:\SQLInstall -ItemType Directory
if ($SQLServerVersion -eq "2016") {
    $ImagePath = 'C:\SQLMedia\SQLServer2016SP1-FullSlipstream-x64-ENU.iso'
} elseif ($SQLServerVersion -eq "2017") {
    $ImagePath = 'C:\SQLMedia\SQLServer2017-x64-ENU.iso'
} else {
    $ImagePath = 'C:\SQLMedia\SQLServer2019-x64-ENU.iso'
}
$mountResult = Mount-DiskImage -ImagePath $ImagePath -PassThru
$volumeInfo = $mountResult | Get-Volume
$driveInfo = Get-PSDrive -Name $volumeInfo.DriveLetter
Copy-Item -Path ( Join-Path -Path $driveInfo.Root -ChildPath '*' ) -Destination C:\SQLInstall\ -Recurse
Dismount-DiskImage -ImagePath $ImagePath

$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName="*"
            CertificateFile = "C:\AWSQuickstart\publickeys\AWSQSDscPublicKey.cer"
            Thumbprint = $DscCertThumbprint
            PSDscAllowDomainUser = $true
        },
        @{
            NodeName = 'localhost'
        }
    )
}

Configuration SQLInstall {
    [CmdletBinding()]
    param (
        [PSCredential] $Credentials,
        [PSCredential] $SQLCredentials
    )

    Import-Module -Name PSDesiredStateConfiguration
    Import-Module -Name SqlServerDsc
    
    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module SqlServerDsc
    
    Node 'localhost'{
        WindowsFeature 'NetFramework35'{
            Name   = 'NET-Framework-Core'
            Ensure = 'Present'
        }
    
        WindowsFeature 'NetFramework45'{
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }
    
        SqlSetup 'InstallDefaultInstance'{
            InstanceName           = 'MSSQLSERVER'
            Features               = 'SQLENGINE,Replication,FullText,Conn'
            SQLCollation           = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSvcAccount          = $SQLCredentials
            AgtSvcAccount          = $SQLCredentials
            SQLSysAdminAccounts    = $ClusterAdminUser, $SQLAdminUser
            ASSysAdminAccounts     = $ClusterAdminUser, $SQLAdminUser
            InstallSharedDir       = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir    = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir            = 'C:\Program Files\Microsoft SQL Server'
            InstallSQLDataDir      = 'D:\MSSQL\Data'
            SQLUserDBDir           = 'D:\MSSQL\Data'
            SQLUserDBLogDir        = 'E:\MSSQL\Log'
            SQLTempDBDir           = 'F:\MSSQL\Temp'
            SQLTempDBLogDir        = 'F:\MSSQL\Temp'
            SQLBackupDir           = 'F:\MSSQL\Backup'
            SourcePath             = 'C:\SQLInstall\'
            UpdateEnabled          = 'False'
            ForceReboot            = $false
            PsDscRunAsCredential   = $Credentials
            DependsOn              = '[WindowsFeature]NetFramework35', '[WindowsFeature]NetFramework45'
        }
    }
}

SQLInstall -OutputPath 'C:\AWSQuickstart\SQLInstall' -ConfigurationData $ConfigurationData -Credentials $Credentials -SQLCredentials $SQLCredentials