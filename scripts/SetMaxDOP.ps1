[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]
    $NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]
    $DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]
    $DomainAdminUser,

    [Parameter(Mandatory=$true)]
    [string]
    $DomainAdminPassword,

    [Parameter(Mandatory=$false)]
    [string]
    $dop="30"
)

try {
    Start-Transcript -Path C:\cfn\log\SetMaxDOP.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    $DomainAdminFullUser = $DomainNetBIOSName + '\' + $DomainAdminUser
    $DomainAdminSecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $DomainAdminCreds = New-Object System.Management.Automation.PSCredential($DomainAdminFullUser, $DomainAdminSecurePassword)

    $SetupMaxDOPPs={
        $sql = "EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE; EXEC sp_configure 'cost threshold for parallelism', " + $Using:dop + "; RECONFIGURE WITH OVERRIDE; "
        Invoke-Sqlcmd -AbortOnError -ErrorAction Stop -Query $sql
    }

    Invoke-Command -Authentication Credssp -Scriptblock $SetupMaxDOPPs -ComputerName $NetBIOSName -Credential $DomainAdminCreds

}
catch {
    $_ | Write-AWSQuickStartException
}
