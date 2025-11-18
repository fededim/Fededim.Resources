<#
.SYNOPSIS

Utility script to obtain and renew a free SSL certificate from Let's Encrypt using win-acme tool and self validation mode.

.DESCRIPTION

You must specify the domain (in $Domain), the possible subject alternate names (in $SubjectAlternativeNames), an email address to associate to the ACME account (in $AcmeEmailAddress) and the certificate password to use (in $CertificatePassword) to store it into $CertificatePath.
You should tweak settings.json file (at least enter the SMTP server settings in order receive an email every time the certificate is renewed)

.PARAMETER Domain
Specifies the domain you own for which you want to obtain the certificate

.PARAMETER SubjectAlternativeNames
Specifies the subject alternate names (e.g. additional domain names) to be secured by the certificate

.PARAMETER AcmeEmailAddress
Email address to link to your ACME account.

.PARAMETER ValidationPort
Specifies a local tcp port which must be forwarded by the external firewall to the server running the script in order to perform domain validation through self validation mode.
Win-Acme during its execution will start locally a simple web server on this port just for exposing a file which will be retrieved by acme server connecting to http://<Domain> (public external port 80) just to verify the ownership of the domain automatically.
If not passed, it defaults to 80.

.PARAMETER CertificatePath
Specifies the path where to save the certificate. If not passed, it defaults to .\config\acme-v02.api.letsencrypt.org\Certificates

.PARAMETER CertificatePassword
Specifies the password used to encrypt the certificate (pem/pfx) stored in $CertificatePath

.PARAMETER Force
Specifies to perform a renewal disregarding the validity of current certificate

.PARAMETER Verbose
Specifies to output a verbose log

.INPUTS

None.

.OUTPUTS

The execution log

.EXAMPLE

PS> .\RequestRenewCertificate.ps1 -Domain "mydomain.com" -SubjectAlternativeNames @("www.mydomain.com","ftp.mydomain.com","vpn.mydomain.com") -AcmeEmailAddress "user@mydomain.com" -CertificatePassword "SecretPassword"

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt
https://www.win-acme.com/reference/cli

.NOTES

© 2024- Federico Di Marco <fededim@gmail.com> released under MIT LICENSE

PREREQUISITES:
- WinAcme use NET Runtime 7.0 which must be installed from here https://dotnet.microsoft.com/it-it/download/dotnet/7.0
- The first time you issue a "winget" command it prompts you to accept the terms for the Microsoft Store, if you never did this, please launch manually "winget" in a prompt and accept the terms, otherwise this script will get stuck indefinitely.

HISTORY:
- Initial version
- 31052025: Removed --ocsp-must-staple parameter since in May 2025 Let's Encrypt removed the support for OCSP Must-Stample (see https://letsencrypt.org/2024/12/05/ending-ocsp/). If you are unable to renew your certificate please delete and recreate the config folder then relaunch the script.
- 18112025: Added notes, fixed installation of win-acme (global flag missing), 

#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()] [Alias('d')] [String] $Domain,
	[Alias('san')] [String[]] $SubjectAlternativeNames,	
	[ValidateNotNullOrEmpty()] [Alias('e')] [String] $AcmeEmailAddress,
	[Alias('pt')] [Nullable[Int16]] $ValidationPort,
	[Alias('cp')] [String] $CertificatePath,
	[ValidateNotNullOrEmpty()] [Alias('p')] [String] $CertificatePassword,
	[Parameter(Mandatory=$false)]  [Alias('f')] [switch] $Force = $false
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

	$verbose = ('-Verbose' -in $MyInvocation.UnboundArguments -or $MyInvocation.BoundParameters.ContainsKey('Verbose'))
	
	# check that win-acme tool is installed, if not install it
	dotnet tool list win-acme | Out-Null
	if ($? -eq $false) {
		Write-Host "Win-Acme is not installed, installing it for current user..."
		dotnet tool install win-acme --create-manifest-if-needed --global
	}
	
	# check that Webadministration module is installed, if not install it
	$module = (Get-WindowsOptionalFeature -FeatureName 'IIS-WebServerManagementTools' -Online)
	if ($module -eq $null -or $($module.State) -eq 'Disabled') {
		Write-Host "Webadministration powershell module is not installed, installing it..."	
		Enable-WindowsOptionalFeature -FeatureName 'IIS-WebServerManagementTools' -Online -All
	}

	# check that OpenSSL is installed, if not install it
	winget list FireDaemon.OpenSSL | Out-Null
	if ($? -eq $false) {
		Write-Host "Openssl is not installed, installing it..."
		winget install FireDaemon.OpenSSL
	}

	Import-Module Webadministration   #for iis management

	# copy setting.json to appropriate folder, unbelievably I was not able to find a way to specify its folder location
	$settingsFolder = (gci -r -Path "$env:USERPROFILE\.dotnet\tools" wacs.dll).DirectoryName
	Write-Host "Copying settings to folder $settingsFolder..."
	copy settings.json $settingsFolder

	# creates the certificate with all the hosts provided in the host parameter
	# registers a scheduled task to update it (after "renewalDays" as specified in configuration file settings.json)
	# sends an email with the result (smtp settings and receiver addresses are defined inside settings.json)

	$additionalHosts = TernaryExpression ($($SubjectAlternativeNames.Count) -eq 0) '' ([System.String]::Join(",",$SubjectAlternativeNames))
	$hosts = $Domain + ',' + $additionalHosts

	if ($ValidationPort -eq $null) {
		$ValidationPort = 80
	}

	if ([System.String]::IsNullOrEmpty($CertificatePath)) {
		$CertificatePath = ".\config\acme-v02.api.letsencrypt.org\Certificates"
	}
	
	$null = New-Item -ItemType Directory -Path $CertificatePath -Force
	$CertificatePath = (Resolve-Path -Path $CertificatePath).Path
	$UpdateIISCertificatesScriptPath = (Resolve-Path -Path ".\UpdateIISCertificates.ps1").Path

	$commandLine = "wacs.exe --accepttos --source manual --host $hosts --validation selfhosting --validationport $ValidationPort --store `"certificatestore,pemfiles,pfxfile`" --setuptaskscheduler --emailaddress $AcmeEmailAddress  --pemfilespath `"$CertificatePath`" --pempassword `"$CertificatePassword`" --pfxfilepath `"$CertificatePath`" --pfxpassword `"$CertificatePassword`" --installation script --script `"$UpdateIISCertificatesScriptPath`" --scriptparameters `"'{CertThumbprint}' 'SEVPNSERVERDEV' '$CertificatePath' '$CertificatePassword'`""
	
	if ($Force -eq $true) {
		$commandLine = $commandLine + " --force --nocache"
	}
	
	if ($verbose -eq $true) {
		$commandLine = $commandLine + " --verbose"
	}
	
	Invoke-Expression $commandLine
	
	# update scheduled tasks working directory with the right one
	$schTask = (Get-ScheduledTask -TaskName "win-acme*") | Sort-Object -Property Date -Descending | Select-Object -First 1
	$action = $schTask.Actions | Select -First 1
	$action.WorkingDirectory = (Resolve-Path -Path '.').Path
	Set-ScheduledTask -TaskName "$($schTask.TaskName)" -Action $action
