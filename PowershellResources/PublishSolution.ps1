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
	[Parameter(Mandatory=$false)]  [Alias('pp')] [String] $PublishingProfile = "FolderProfile"
	)

function Get-Timestamp {
    return "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]"
}

$ErrorActionPreference = 'Stop'

if ([String]::IsNullOrEmpty($SolutionName)) {
	$SolutionName = (Get-ChildItem -Filter *.sln* -Recurse -File | Select-Object -First 1).BaseName
}

$UNCDeployFolder = $DeployFolder -replace '^([A-Za-z]):', "\\$Server\`$1`$"
$ServerUnc = $UNCDeployFolder.Substring(0, $UNCDeployFolder.IndexOf('$')+1)

$ServerNewFolder = "$($SolutionName)New"
$ServerOldFolder = "$($SolutionName)Old"

Write-Host "$(Get-Timestamp) Publishing solution: $SolutionName`n" -Foreground Cyan
Remove-Item $PublishFolder -Recurse -Force -ErrorAction Ignore
dotnet publish $SolutionName -p:PublishProfile=$PublishingProfile -p:EnvironmentName=Production
Remove-Item $PublishFolder\appsettings.DEVELOPMENT.json -Force

$credentials = (Get-Credential -Message "Connecting to server: $Server`n")

Write-Host "`n$(Get-Timestamp) Mapping samba UNC: $ServerUnc`n" -Foreground Cyan
New-SmbMapping -RemotePath "$ServerUnc" -Credential $credentials

$remoteSession = New-PSSession -ComputerName "$Server" -Credential $credentials

try {
	$folderToDelete = "$UNCDeployFolder\$ServerNewFolder"
	if ([System.IO.Directory]::Exists($folderToDelete)) {
		Write-Host "`n$(Get-Timestamp) Deleting folder $folderToDelete" -Foreground Cyan
		[System.IO.Directory]::Delete($folderToDelete,$true)
	}

	$folderToDelete = "$UNCDeployFolder\$ServerOldFolder"
	if ([System.IO.Directory]::Exists($folderToDelete)) {
		Write-Host "`n$(Get-Timestamp) Deleting folder $folderToDelete" -Foreground Cyan
		[System.IO.Directory]::Delete($folderToDelete,$true)
	}

	Write-Host "`n$(Get-Timestamp) Copying folder $PublishFolder to $ServerRootFolder\$ServerNewFolder..." -Foreground Cyan
	robocopy "$PublishFolder" "$UNCDeployFolder\$ServerNewFolder" /E /MT:16 /R:3 /W:5 /NFL /NDL /NJH /NP /NC /NS

	Invoke-Command -Session $remoteSession {
		Import-Module WebAdministration
		
		$appPoolState = (Get-WebAppPoolState -Name $using:AppPool)

		if ($($appPoolState.Value) -ne "Stopped") {
			Write-Host "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Stopping AppPool $using:AppPool (Status $($appPoolState.Value))..." -Foreground Green

			Stop-WebAppPool -Name $using:AppPool
			
			while ((Get-WebAppPoolState -Name $using:AppPool).Value -ne "Stopped") {
				Start-Sleep -Seconds 1
			}

			Write-Host "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] AppPool $using:AppPool successfully stopped."  -Foreground Green
		}

	} 6>&1

	Write-Host "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Renaming folder $DeployFolder\$SolutionName to $DeployFolder\$ServerOldFolder on server $Server..." -Foreground Cyan
	[System.IO.Directory]::Move("$UNCDeployFolder\$SolutionName","$UNCDeployFolder\$ServerOldFolder")

	Write-Host "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Renaming folder $DeployFolder\$ServerNewFolder to $DeployFolder\$SolutionName on server $Server..." -Foreground Cyan
	[System.IO.Directory]::Move("$UNCDeployFolder\$ServerNewFolder","$UNCDeployFolder\$SolutionName")

	Invoke-Command -Session $remoteSession {
		Write-Host "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting AppPool $using:AppPool..." -Foreground Green
		Start-WebAppPool -Name $using:AppPool
	}
}
finally {
	Remove-PSSession -Session $remoteSession
	Remove-SmbMapping -RemotePath "$ServerUnc" -Force
}
