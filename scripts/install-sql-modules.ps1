[CmdletBinding()]
param()

"Setting up Powershell Gallery to Install DSC Modules"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

"Installing the needed Powershell DSC modules for this Quick Start"
Install-Module -Name SqlServerDsc -RequiredVersion 14.2.1
Install-Module -Name ComputerManagementDsc -RequiredVersion 8.4.0
Install-Module -Name xFailOverCluster -RequiredVersion 1.14.1
Install-Module -Name PSDscResources -RequiredVersion 2.12.0.0
Install-Module -Name xSmbShare -RequiredVersion 2.2.0.0
Install-Module -Name StorageDsc -RequiredVersion 5.0.1
Install-Module -Name ActiveDirectoryDsc -RequiredVersion 6.0.1
Install-Module SqlServer -Force -AllowClobber -RequiredVersion 21.1.18226

"Disabling Windows Firewall"
Get-NetFirewallProfile | Set-NetFirewallProfile -Enabled False

"Creating Directory for DSC Public Cert"
New-Item -Path C:\AWSQuickstart\publickeys -ItemType directory -Force

"Removing DSC Certificate if it already exists"
(Get-ChildItem Cert:\LocalMachine\My\) | Where-Object { $_.Subject -eq "CN=AWSQSDscEncryptCert" } | Remove-Item

If (-Not (Get-ChildItem -path cert:\LocalMachine\My | Where-Object { $_.subject -eq "CN=AWSQSDscEncryptCert" })) {
  "Setting up DSC Certificate to Encrypt Credentials in MOF File"
  $cert = New-SelfSignedCertificate -Type DocumentEncryptionCertLegacyCsp -DnsName 'AWSQSDscEncryptCert' -HashAlgorithm SHA256
  # Exporting the public key certificate
  $cert | Export-Certificate -FilePath "C:\AWSQuickstart\publickeys\AWSQSDscPublicKey.cer" -Force
}

