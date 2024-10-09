[CmdletBinding()]
param(
	[Parameter(Mandatory=$false)]  [Alias('u')] [String] $User = "<azure devops user email>m",
	[Parameter(Mandatory=$false)]  [Alias('r')] [String[]] $Repositories = @("repo1","repo2","repo3"),
	[Parameter(Mandatory=$false)]  [Alias('f')] [AllowNull()] [Nullable[System.DateTime]] $From,
	[Parameter(Mandatory=$false)]  [Alias('t')] [AllowNull()] [Nullable[System.DateTime]] $To,
	[Parameter(Mandatory=$false)]  [Alias('l')] [AllowNull()] [Nullable[System.Int32]] $LastDays,
	[Parameter(Mandatory=$false)]  [Alias('lc')] [AllowNull()] [Nullable[System.Int32]] $MaxCommits = 10
	)

$pat = "<personal access token>"
$organization = "https://dev.azure.com/<organization>"
$project = "<project>"

# Create the authorization header
$encodedCredentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(":"+$pat))
$headers = @{
    Authorization = "Basic $encodedCredentials"
}

if ($LastDays -ne $null -and $From -eq $null) {
	$From = [System.DateTime]::Now.AddDays(-$LastDays)
}

if ($Repositories -eq $null) {
	$repos = (az repos list --organization $organization --project $project) | ConvertFrom-Json
	$Repositories = $repos.name
}	
	
foreach ($repo in $Repositories) {
	$queryUrl = "$organization/$project/_apis/git/repositories/$repo/commits?searchCriteria.author=$User"

	if ($From -ne $null) {
		$queryUrl = $queryUrl + "&searchCriteria.fromDate=$($From.ToString("s"))&searchCriteria.showOldestCommitsFirst=true"
	}

	if ($To -ne $null) {
		$queryUrl = $queryUrl + "&searchCriteria.toDate=$($To.ToString("s"))"
	}

	if ($From -eq $null -or $To -eq $null) {
		$queryUrl = $queryUrl + "&searchCriteria.`$top=$MaxCommits"
	}

	Write-Host "`nRepo $repo`: query $queryUrl`n"
	$commits = (Invoke-RestMethod -Uri $queryUrl -Headers $headers -Method Get)
	if ($commits.value -ne $null) {
		foreach ($commit in $commits.value) {
			Write-Host "$($commit.author.date) $($commit.comment)"	
		}
	}
}
