<#
.SYNOPSIS

Utility to recreate a sitemap.xml file of a website.

.DESCRIPTION

You must specify both the root folder and the domain name

.PARAMETER RootFolder
Specifies the root folder of the website

.PARAMETER Domain
Specifies the domain url (including http or https)

.PARAMETER FileMatchingRegex
Specifies a regex pattern which matches the files to index (by default .html or .htm or .pdf)

.INPUTS

None.

.OUTPUTS

- Creates a sitemap.xml file inside RootFolder
- Logs information.

.EXAMPLE

PS> RecreateSitemapXml.ps1 -RootFolder C:\inetpub\wwwroot -Domain https://fededim.github.io

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2025 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()] [Alias('f')] [String] $RootFolder,
	[ValidateNotNullOrEmpty()] [Alias('d')] [String] $Domain,
	[ValidateNotNullOrEmpty()] [Alias('r')] [String] $FileMatchingRegex = "(\.htm(l)|\.pdf|\.md|\.mp3|\.mp4)"
)

$domainUri = New-Object System.Uri($Domain)
$xmlWriter = New-Object System.XML.XmlTextWriter((Join-Path $RootFolder "sitemap.xml" -Resolve),$Null)
$originalPath = (Get-Location).Path
$resolvedRootFolder = Resolve-Path -Path $RootFolder

try {
	Set-Location $RootFolder
	$xmlWriter.Formatting = 'Indented'
	$xmlWriter.Indentation = 1
	$xmlWriter.IndentChar = "`t"


	$xmlWriter.WriteStartDocument()
	$xmlWriter.WriteStartElement('urlset','http://www.sitemaps.org/schemas/sitemap/0.9')

	foreach ($fileEntry in (Get-ChildItem -Recurse -File -Path $resolvedRootFolder)) {	
		if ((!($fileEntry.Name -match $FileMatchingRegex)) -or ($fileEntry.Name.StartsWith("google"))) {
			continue;
		}

		if (($fileEntry.Name -eq "index.html") -or ($fileEntry.Name -eq "index.htm")) {
			$xmlWriter.WriteStartElement('url')
			$xmlWriter.WriteElementString('loc',$domainUri.ToString())
			$xmlWriter.WriteElementString('lastmod',$fileEntry.LastWriteTime.ToString("o"))
			$xmlWriter.WriteElementString('priority','1.00')
			$xmlWriter.WriteEndElement()

			Write-Host "Added $($domainUri.ToString()) LastModified $($fileEntry.LastWriteTime)"
		}

		$fileEntryRelativePath = (Resolve-Path -Relative -Path $fileEntry.FullName)
		$fileEntryRelativePath
		
		$fileEntryRelativePathUri = New-Object System.Uri($fileEntryRelativePath.Replace("\","/"),[System.UriKind]::Relative)
		$fileEntryUri = New-Object System.Uri($domainUri, $fileEntryRelativePath)

		$escapedFileEntryUri = [System.Uri]::EscapeDataString($fileEntryUri.ToString()).Replace("https%3A%2F%2F","https://").Replace("%2F","/")
		
		$xmlWriter.WriteStartElement('url')
		$xmlWriter.WriteElementString('loc',$escapedFileEntryUri)
		$xmlWriter.WriteElementString('lastmod',$fileEntry.LastWriteTime.ToString("o"))
		$xmlWriter.WriteElementString('priority','1.00')
		$xmlWriter.WriteEndElement()

		Write-Host "Added $($fileEntryUri.ToString()) LastModified $($fileEntry.LastWriteTime)`n"
	}
}
finally {
	$xmlWriter.WriteEndDocument()
	$xmlWriter.Flush()
	$xmlWriter.Close()
	
	Set-Location $originalPath
}