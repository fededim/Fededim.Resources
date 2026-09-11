<#
.SYNOPSIS

Utility to publish a Visual Studio solution to a local folder using a publishing profile and uploaded it to a remote IIS server

.DESCRIPTION

CLIENT PREREQUISITE: You need to trust on the machine executing the script the destination server you want to connect to inside WinRM TrustedHosts
RUN ON CLIENT: Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<remote server ip or name>"

You must specify the Server (in $Server), the local relative publish folder (in $PublishFolder), the deploy folder on server (in $DeployFolder, using administrative shares notation, e.g. "c$\..."), the AppPool name to be stopped/started (in $AppPool).

.PARAMETER Server
Specifies the server ip address or name where to publish the solution

.PARAMETER PublishFolder
Specifies the local relative publish folder

.PARAMETER DeployFolder
Specifies the deploy folder on server, using administrative shares notation, e.g. "c$\..."

.PARAMETER AppPool
Specifies the application pool to be stopped/started for the copy operation

.PARAMETER SolutionName
Specifies the solution name without extension. If empty, it automatically searches for a file with extension .sln or slnx and publishes the first one found

.PARAMETER RemoteDriveName
Specifies the remote drive name to use to mount the remote UNC share of destination server.

.PARAMETER PublishingProfile
Specifies the publishing profile name. Defaults to "FolderProfile".

.INPUTS

None.

.OUTPUTS

None

.EXAMPLE

PS> PublishProfile -Server "<server name or ip>" -PublishFolder ".\<solution name>\bin\Release\net10.0\win-x64\publish" -DeployFolder "c$\inetpub\wwwroot\<site>" -AppPool "<Application pool name in IIS>"

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2026 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()]  [Alias('s')] [String] $Server,
	[ValidateNotNullOrEmpty()]  [Alias('p')] [String] $PublishFolder,
	[ValidateNotNullOrEmpty()]  [Alias('d')] [String] $DeployFolder,
	[ValidateNotNullOrEmpty()]  [Alias('a')] [String] $AppPool,
    [Parameter(Mandatory=$false)]  [Alias('sn')] [String] $SolutionName,
	[Parameter(Mandatory=$false)]  [Alias('r')] [String] $RemoteDriveName = "Server",
	[Parameter(Mandatory=$false)]  [Alias('pp')] [String] $PublishingProfile = "FolderProfile"
	)

$ErrorActionPreference = 'Stop'

$ServerFolder = "\\$Server\$DeployFolder"

if ([String]::IsNullOrEmpty($SolutionName)) {
	$SolutionName = (Get-ChildItem -Filter *.sln* -Recurse -File | Select-Object -First 1).BaseName
}

Write-Host "Publishing solution: $SolutionName`n"
Remove-Item $PublishFolder -Recurse -Force -ErrorAction Ignore
dotnet publish $SolutionName -p:PublishProfile=$PublishingProfile -p:EnvironmentName=Production
Remove-Item $PublishFolder\appsettings.DEVELOPMENT.json -Force

$credentials = (Get-Credential -Message "Connecting to server: $Server`n")

New-PSDrive -Name $remoteDriveName -PSProvider "FileSystem" -Root $ServerFolder -Credential $credentials
$remoteSession = New-PSSession -ComputerName $Server -Credential $credentials

Invoke-Command -Session $remoteSession {
	Import-Module WebAdministration
	$appPoolState = (Get-WebAppPoolState -Name $using:AppPool)

	if ($($appPoolState.Value) -ne "Stopped") {
		Write-Host "`nStopping AppPool $using:AppPool (Status $($appPoolState.Value))..."

		Stop-WebAppPool -Name $using:AppPool
	}
} 6>&1

Start-Sleep -Seconds 5

Write-Host "`nCopying folder $PublishFolder to $ServerFolder"
Remove-Item "${remoteDriveName}:\*" -Recurse -Force 
Copy-Item -Path "$PublishFolder\*" -Destination "${remoteDriveName}:\" -Recurse

Invoke-Command -Session $remoteSession {
	Write-Host "`nStarting AppPool $using:AppPool..."
	Start-WebAppPool -Name $using:AppPool
}

Remove-PsDrive -Name $remoteDriveName -Force
Remove-PSSession -Session $remoteSession


