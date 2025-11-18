<#
.SYNOPSIS

Utility script to perform unattended update of SSL certificate onto IIS and Softether VPN Service. For IIS the website binding hostname should be contained in either the certificate name or subject alternatives names.

.DESCRIPTION

You must specify the certificate thumbprint for IIS and also SoftEthervpnServiceName, CertificatesPath and PemPassword in order to update Softether VPN Server

.PARAMETER Thumbprint
Specifies the thumbprint of the certificate which must be updated onto IIS.

.PARAMETER SoftEthervpnServiceName
Specifies the service name used by softether vpn service (usually SEVPNSERVER)

.PARAMETER CertificatesPath
Specifies the folder where the certificate files are located according to WinAcme structure (should contain a subfolder name with the certificate domain containing the (encrypted) private key in pem format, e.g. the file <domain name>\<domain name>-key.pem)

.PARAMETER PemPassword
Specifies the password used to encrypt the certificate files (pem/pfx) stored in $CertificatePath

.INPUTS

None.

.OUTPUTS

The execution log.

.EXAMPLE

PS> .\UpdateIISCertificates.ps1 '9715D0A2ACCC674BDB23D10B567B514AFA8F4249' 'SEVPNSERVER' 'C:\temp\WinAcme\config\acme-v02.api.letsencrypt.org\Certificates' 'PemPassword'

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt
https://www.win-acme.com/reference/cli

.NOTES

© 2024- Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 

HISTORY:
- Initial version
- 18112025: fixed error on probing SoftetherVpn service, the wmic tool has been removed from Windows since 25H2 version --> switched to Get-cimInstance
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()] [Alias('t')] [String] $Thumbprint,
	[Alias('s')] [String] $SoftEthervpnServiceName,
	[Alias('cp')] [String] $CertificatesPath,
	[Alias('p')] [String] $PemPassword
	)
	
	Import-Module Webadministration   #for iis management
	
	#Write-Host "Thumbprint $Thumbprint ServiceName $SoftEthervpnServiceName $CertificatesPath PemPassword $PemPassword"
	
	# updates the certificate on the https website found on the local IIS
	if ($? -eq $true) {
		$hostingCertificates = (Get-ChildItem Cert:\LocalMachine\WebHosting)
		$certificate = ($hostingCertificates | Where { $_.Thumbprint -eq "$Thumbprint" })
		$certificateNames = $certificate.GetName() + "`n" + ($certificate.Extensions | Where-Object {$_.Oid.FriendlyName -eq "Subject Alternative Name"}).format($true)
		
		Write-Host "Hostnames contained in the certificate with thumbprint: $Thumbprint`n$certificateNames`n"
		
		foreach ($site in (Get-ChildItem -Path "IIS:\Sites")) {
			foreach ($binding in ($site.Bindings.Collection | Where {( $_.protocol -eq 'https')})) {
				$bindingHostname = ($($binding.bindingInformation) -split ":")[-1]
				
				if ($($binding.certificateHash) -ne $certificate.Thumbprint -and $certificateNames -like "*$bindingHostname*") {
					$binding.AddSslCertificate($certificate.Thumbprint, "WebHosting")
					Write-Host "`nUpdated certificate on site $($Site.Name) binding $($binding.bindingInformation) with thumbprint $($certificate.Thumbprint) expiry date $($certificate.NotAfter)"
				}
			}
		}


		$softEtherVpnServer = (Get-cimInstance win32_service -Filter "name like '$SoftEthervpnServiceName'")
		#Update certificate on Soft Ethervpn server
		if ($softEtherVpnServer -ne $null -and ![String]::IsNullOrEmpty($CertificatesPath)) {
			Write-Host "Updating sothether vpn certificate..."

			net stop $SoftEthervpnServiceName
			$serviceFolder = Split-Path ($softEtherVpnServer.PathName)
			$vpnServerConfigFile = Join-Path $serviceFolder vpn_server.config
			$vpnServerConfig = Get-Content "$vpnServerConfigFile"
			$domainName = $certificate.GetName().Replace('CN=','')
			$keyFile = Join-Path $CertificatesPath "$domainName-key.pem"

			Write-Host "ServiceFolder $ServiceFolder VpnServerConfigFile $vpnServerConfigFile DomainName $domainName Keyfile $keyFile"

			if (![System.String]::IsNullOrEmpty($PemPassword)) {
				Write-Host "Decrypting encrypted private key with OpenSSL..."
				$key = -join((openssl rsa -passin pass:$PemPassword -in "$keyFile") -replace "-----.+","")
			}
			else {
				$key = ((Get-Content "$keyFile") -replace "-----.+","")
			}		 	 
			$crt = [System.Convert]::ToBase64String($certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))

			# multiline cert0 regexp (for future): (?msi)(declare Cert0\s+\{\s+)([^}]+$)
			# done test using .\vpncmd.exe but you can't pass $PemPassword as paramater /SERVER localhost /PASSWORD:<password> /CMD ServerCertSet /LOADCERT:"<unencrypted crt pem file>" /LOADKEY:"<unencrypted private key pem file>"
			 
			cp "$vpnServerConfigFile" "$vpnServerConfigFile.old"
			$vpnServerConfig = $vpnServerConfig -replace "(byte ServerCert ).+","`$1$crt"
			$vpnServerConfig = $vpnServerConfig -replace "(byte ServerKey ).+","`$1$key"
			Set-Content -Path "$vpnServerConfigFile" -Value $vpnServerConfig

			dir "$vpnServerConfigFile*"
			net start $SoftEthervpnServiceName
		}
		
		Write-Host "All done!"
	}
