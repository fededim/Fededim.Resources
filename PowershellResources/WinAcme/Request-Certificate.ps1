# install winacme once globally: dotnet tool install win-acme --global

Import-Module Webadministration

# creates the certificate with all the hosts provided in the host parameter, registers a scheduled task to update it (after "renewalDays" as specified in configuration file settings.json) and sends an email with the result (smtp settings are defined inside settings.json)
# validationport should be a tcp port forwarded to the domain server running the script, win-acme in order to validate the domain during its execution will run an its own web server on this port (http only) just for the duration of the domain validation.

.\wacs.exe --accepttos --source manual --host "fdm-in.freeddns.org,www.fdm-in.freeddns.org,vpn.fdm-in.freeddns.org,homeassistant.fdm-in.freeddns.org" --validation selfhosting --validationport 8082 --store "certificatestore,pemfiles,pfxfile" --setuptaskscheduler --emailaddress "federico.dimarco@gmail.com" --ocsp-must-staple

# this code updates the certificate on the https website found on the local IIS

$lastCertificate = ((Get-ChildItem Cert:\LocalMachine\WebHosting ) | Where { $_.SubjectName.Name -like '*fdm-in.freeddns.org*' -and $_.NotAfter -ge (Get-Date) })[0]

foreach ($site in (Get-ChildItem -Path "IIS:\Sites")) {
	foreach ($binding in ($site.Bindings.Collection | where {( $_.protocol -eq 'https')})) {
		$binding.AddSslCertificate($lastCertificate.Thumbprint, "WebHosting")
		Write-Host "`nUpdated certificate on site $($Site.Name) binding $($binding.bindingInformation) with thumbprint $($lastCertificate.Thumbprint) expiry date $($lastCertificate.NotAfter)"
	}
}
