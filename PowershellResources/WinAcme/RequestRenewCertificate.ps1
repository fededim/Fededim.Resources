<#
.SYNOPSIS

Utility script to obtain and renew a free SSL certificate from Let's Encrypt using win-acme tool and self validation mode.

.DESCRIPTION

You must specify the Azure Devops user email (in $User), the organization (in $Organization), the project (in $Project) and a personal access token (in $Pat)

.PARAMETER Domain
Specifies the domain you own for which you want to obtain the certificate

.PARAMETER SubjectAlternativeNames
Specifies the subject alternate names (e.g. additional domain names) to be secured by the certificate

.PARAMETER AcmeEmailAddress
Email address to link to your ACME account.

.PARAMETER ValidationPort
Specifies a local tcp port which must be forwarded by the external firewall to the server running the script in order to perform domain validation through self validation mode.
Win-Acme during its execution will start locally a simple web server on this port just for exposing a file which will be retrieved by acme server connecting to http://<Domain> (public external port 80) just to verify the ownership of the domain automatically.

.INPUTS

None.

.OUTPUTS

The execution log

.EXAMPLE

PS> 

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt
https://www.win-acme.com/reference/cli

.NOTES

© 2024 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()] [Alias('d')] [String] $Domain = "fdm-in.freeddns.org",
	[Alias('san')] [String[]] $SubjectAlternativeNames = @("www.fdm-in.freeddns.org","vpn.fdm-in.freeddns.org","homeassistant.fdm-in.freeddns.org"),	
	[ValidateNotNullOrEmpty()] [Alias('e')] [String] $AcmeEmailAddress = "federico.dimarco@gmail.com",
	[ValidateNotNullOrEmpty()] [Alias('p')] [Int16] $ValidationPort = 8082
	)

	function TernaryExpression {
		Param (
			[Parameter(Mandatory=$true)] [System.Boolean] $booleanExpression,
			[Parameter(Mandatory=$false)] $TrueExpression,
			[Parameter(Mandatory=$false)] $FalseExpression
		)

		if ($booleanExpression) {
			,$TrueExpression
		}
		else {
			,$FalseExpression
		}
	}

	# check that win-acme tool is installed, if not install it
	dotnet tool list win-acme | Out-Null
	if ($? -eq $false) {
		Write-Host "Win-Acme not installed, installing it for current user..."
		dotnet tool install win-acme --create-manifest-if-needed
	}
	
	# check that Webadministration module is installed, if not install it
	$module = (Get-WindowsOptionalFeature -FeatureName 'IIS-WebServerManagementTools' -Online)
	if ($module -eq $null) {
		Write-Host "Webadministration powershell module not installed, installing it..."	
		Enable-WindowsOptionalFeature -FeatureName 'IIS-WebServerManagementTools' -Online -All
	}

	Import-Module Webadministration   #for iis management

	# copy setting.json to appropriate folder, unbelievably I was not able to find a way to specify its folder location
	$settingsFolder = (gci -r -Path "$env:USERPROFILE\.dotnet\tools" wacs.dll).DirectoryName
	Write-Host "Copying settings to folder $settingsFolder..."
	copy settings.json $settingsFolder

	# creates the certificate with all the hosts provided in the host parameter
	# registers a scheduled task to update it (after "renewalDays" as specified in configuration file settings.json)
	# sends an email with the result (smtp settings and receiver addresses are defined inside settings.json)

	$AdditionalHosts = TernaryExpression ($($SubjectAlternativeNames.Count) -eq 0) '' ([System.String]::Join(",",$SubjectAlternativeNames))
	$Hosts = $Domain + ',' + $AdditionalHosts

	# add --verbose for troubleshooting
	wacs.exe --accepttos --source manual --host $Hosts --validation selfhosting --validationport $ValidationPort --store "certificatestore,pemfiles,pfxfile" --setuptaskscheduler --emailaddress $AcmeEmailAddress  --ocsp-must-staple

	# updates the certificate on the https website found on the local IIS
	if ($? -eq $true) {
		$lastCertificate = ((Get-ChildItem Cert:\LocalMachine\WebHosting ) | Where { $_.SubjectName.Name -like "*$Domain*" -and $_.NotAfter -ge (Get-Date) })[0]

		foreach ($site in (Get-ChildItem -Path "IIS:\Sites")) {
			foreach ($binding in ($site.Bindings.Collection | where {( $_.protocol -eq 'https')})) {
				$binding.AddSslCertificate($lastCertificate.Thumbprint, "WebHosting")
				Write-Host "`nUpdated certificate on site $($Site.Name) binding $($binding.bindingInformation) with thumbprint $($lastCertificate.Thumbprint) expiry date $($lastCertificate.NotAfter)"
			}
		}
	}
