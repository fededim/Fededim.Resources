<#
.SYNOPSIS

Utility script to update all certificates of all IIS websites. The website binding hostname should be contained in either the certificate name or subject alternatives names.

.DESCRIPTION

You must specify the certificate thumbprint in $Thumbprint

.PARAMETER Thumbprint
Specifies the new certificate thumbprint to assign to IIS website bindings

.INPUTS

None.

.OUTPUTS

The execution log.

.EXAMPLE

PS> .\UpdateIISCertificates.ps1 "EE99B99ABFFE06294956CB03D2C441975406C893"

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt
https://www.win-acme.com/reference/cli

.NOTES

© 2024 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()] [Alias('d')] [String] $Thumbprint
	)
	
	Import-Module Webadministration   #for iis management
	
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
	}
