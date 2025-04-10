<#
.SYNOPSIS

Utility to perform indexing of webpages through IndexNow of one or more domains using the website sitemap.xml.

.DESCRIPTION

You must specify the domain name and the indexNow key in the input hashtable parameter DomainsToBeIndexed

.PARAMETER DomainsToBeIndexed
Specifies the hashtable consisting of the domain name with the associated IndexNow key

.INPUTS

None.

.OUTPUTS

Log information.

.EXAMPLE

PS> IndexNowIndexWebsites.ps1 -DomainsToBeIndexed @{
	"<domain 1>" = '<index now key 1>'
	"<domain 2>" = '<index now key 2>'
}

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2025 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()] [Alias('d')] [Hashtable] $DomainsToBeIndexed = @{
		"www.fdm-in.freeddns.org" = '4c6a24f07fb641b19a43d02ce5a35738'
		"fededim.github.io" = 'b90e22c7680d4d4fbf051bc68004064e'
	}
)

foreach ($keyValuePair in $DomainsToBeIndexed.GetEnumerator()) {
	# Check existance of IndexNow key and that it is equal to the provided key
	$indexNowKeyLocation = "https://$($keyValuePair.Name)/$($keyValuePair.Value).txt"
	$sitemapLocation = "https://$($keyValuePair.Name)/sitemap.xml"

	try {
		$response = (Invoke-WebRequest -Method Get -Uri $indexNowKeyLocation -UseBasicParsing -ErrorAction SilentlyContinue)
	}
	catch {}
	
	if ($? -ne $true -or $keyValuePair.Value -ne $response.Content) {
		Write-Host "Domain $($keyValuePair.Name) IndexNowKey $($keyValuePair.Value) is missing or different at location $indexNowKeyLocation!`n" -ForegroundColor Red
		Continue
	}

	# Extract webpages from sitemap.xml
	try {
		$response = (Invoke-WebRequest -Method Get -Uri $sitemapLocation -UseBasicParsing -ErrorAction SilentlyContinue)
	}
	catch {}

	if ($? -ne $true -or $response.StatusCode -ge 300 -or [System.String]::IsNullOrEmpty($response.Content)) {
		Write-Host "Domain $($keyValuePair.Name) sitemap at $sitemapLocation is missing or broken!`n" -ForegroundColor Red
		Continue
	}

	[xml]$sitemap = $response.Content
	$pages = @($sitemap.urlset.url.loc)

	$indexNowBody = @{
	  "host" = $($keyValuePair.Name)
	  "key" = $($keyValuePair.Value)
	  "keyLocation" = $indexNowKeyLocation
	  "urlList" = $pages
	} | ConvertTo-Json
	
	$response = (Invoke-WebRequest -Method Post -Uri "https://api.indexnow.org/indexnow" -Body $indexNowBody -ContentType "application/json")

	if ($? -ne $true -or $response.StatusCode -ge 300) {
		Write-Host "Error while indexing Domain $($keyValuePair.Name) SearchEngine $searchEngine StatusCode $($response.StatusCode) Content $($response.Content)" -ForegroundColor Red
		$indexNowBody
		$response
	}
	else {
		Write-Host "Domain $($keyValuePair.Name) submitted to IndexNow successfully!`nIndexed pages:" -ForegroundColor Green
		$pages
		Write-Host "`n"
	}
}

