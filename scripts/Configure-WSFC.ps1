[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]
    $WSFCName,
    
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
    $WSFCNode1NetBIOSName,

    [Parameter(Mandatory=$false)]
    [string]
    $WSFCNode2NetBIOSName,

    [Parameter(Mandatory=$false)]
    [string]
    $WSFCNode3NetBIOSName=$null,

    [Parameter(Mandatory=$false)]
    [string]
    $WSFCNode1PrivateIP2,

    [Parameter(Mandatory=$false)]
    [string]
    $WSFCNode2PrivateIP2,

    [Parameter(Mandatory=$false)]
    [string]
    $WSFCNode3PrivateIP2=$null,

    [Parameter(Mandatory=$false)]
    [string]
    $NetBIOSName

)
try {
    Start-Transcript -Path C:\cfn\log\Configure-WSFC.ps1.txt -Append
    $ErrorActionPreference = "Stop"

    $DomainAdminFullUser = $DomainNetBIOSName + '\' + $DomainAdminUser
    $DomainAdminSecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $DomainAdminCreds = New-Object System.Management.Automation.PSCredential($DomainAdminFullUser, $DomainAdminSecurePassword)

    $ConfigWSFCPs={
        $nodes = $Using:WSFCNode1NetBIOSName, $Using:WSFCNode2NetBIOSName
        $addr =  $Using:WSFCNode1PrivateIP2, $Using:WSFCNode2PrivateIP2
        New-Cluster -Name $WSFCName -Node $nodes -StaticAddress $addr
    }
    if ($WSFCNode3NetBIOSName) {
        $ConfigWSFCPs={
            $nodes = $Using:WSFCNode1NetBIOSName, $Using:WSFCNode2NetBIOSName, $Using:WSFCNode3NetBIOSName
            $addr =  $Using:WSFCNode1PrivateIP2, $Using:WSFCNode2PrivateIP2, $Using:WSFCNode3PrivateIP2
            New-Cluster -Name WSFCluster1 -Node $nodes -StaticAddress $addr
        }
    }

    Invoke-Command -Authentication Credssp -Scriptblock $ConfigWSFCPs -ComputerName $NetBIOSName -Credential $DomainAdminCreds
}
catch {
    $_ | Write-AWSQuickStartException
}
