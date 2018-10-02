[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]
    $WSFCName,

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminPassword,

    [Parameter(Mandatory=$true)]
    [string]$FileServerNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$SQLServiceAccount

)

Try{
    Start-Transcript -Path C:\cfn\log\Set-Folder-Permissions.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    $DomainAdminFullUser = $DomainNetBIOSName + '\' + $DomainAdminUser
    $DomainAdminSecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $DomainAdminCreds = New-Object System.Management.Automation.PSCredential($DomainAdminFullUser, $DomainAdminSecurePassword)

    $SetPermissions={
        $ErrorActionPreference = "Stop"
        $timeoutMinutes=30
        $intervalMinutes=1
        $elapsedMinutes = 0.0
        $startTime = Get-Date
        $stabilized = $false

        While (($elapsedMinutes -lt $timeoutMinutes)) {
            try {
                $acl = Get-Acl C:\witness
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule( $Using:obj, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
                $acl.AddAccessRule($rule)
                Set-Acl C:\witness $acl
                $stabilized = $true
                break
            } catch {
                Start-Sleep -Seconds $($intervalMinutes * 60)
                $elapsedMinutes = ($(Get-Date) - $startTime).TotalMinutes
            }
        }

        if ($stabilized -eq $false) {
            Throw "Item did not propgate within the timeout of $Timeout minutes"
        }

    }

    $obj = $DomainNetBIOSName + '\' + $WSFCName + '$'
    Invoke-Command -ScriptBlock $SetPermissions -ComputerName $FileServerNetBIOSName -Credential $DomainAdminCreds

    $obj = $DomainNetBIOSName + '\' + $SQLServiceAccount
    Invoke-Command -ScriptBlock $SetPermissions -ComputerName $FileServerNetBIOSName -Credential $DomainAdminCreds

}
Catch{
    $_ | Write-AWSQuickStartException
}
