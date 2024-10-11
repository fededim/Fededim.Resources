<#
.SYNOPSIS

Utility to list user commits using Azure Devops REST API among all repositories and all their branches.

.DESCRIPTION

You must specify the Azure Devops user email (in $User), the organization (in $Organization), the project (in $Project) and a personal access token (in $Pat)

.PARAMETER User
Specifies the user email whose commits will be listed.

.PARAMETER Pat
Specifies the personal access token with code (read and status) permissions.

.PARAMETER Organization
Specifies the Azure Devops organization

.PARAMETER Project
Specifies the Azure Devops project

.PARAMETER Repositories
Specifies an array of repositories which will be queried for user commits, e.g. @("repo1","repo2", etc.). If not passed, all repositories of the Azure Devops organization will be queried.

.PARAMETER From
Specifies the starting date after which the commits will be returned.

.PARAMETER To
Specifies the ending date before which the commits will be returned.

.PARAMETER LastDays
It is a shortcut for setting From parameter to CurrentDate - LastDays, used only if From parameter is not passed.

.PARAMETER MaxCommits
Specifies the maximum number of commits which will be retrieved, defaults to 10.

.INPUTS

None.

.OUTPUTS

A list of user commits matching the above parameters. The returned information contains:
- Commit date
- Commit comment
- Commit hash

.EXAMPLE

PS> AzureDevopsQueryUserCommits -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token>

- Returns the last 10 commits from all repositories inside the organization among all branches

PS> AzureDevopsQueryUserCommits -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token> -To "2024-06-01T12:56:34" -MaxCommits 50

- Returns the last 50 commits from all repositories inside the organization among all branches done before 1 June 2024, 12:56:34

PS> AzureDevopsQueryUserCommits -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token> -From "2024-06-01T12:56:34" -MaxCommits 15

- Returns the first 15 commits from all repositories inside the organization among all branches done after 1 June 2024, 12:56:34

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.TXT

.NOTES

© 2024 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory=$true)]  [Alias('u')] [String] $User,
	[Parameter(Mandatory=$true)]  [Alias('a')] [String] $Pat,
	[Parameter(Mandatory=$true)]  [Alias('o')] [String] $Organization,
	[Parameter(Mandatory=$true)]  [Alias('p')] [String] $Project,
	[Parameter(Mandatory=$false)]  [Alias('r')] [String[]] $Repositories,
	[Parameter(Mandatory=$false)]  [Alias('f')] [AllowNull()] [Nullable[System.DateTime]] $From,
	[Parameter(Mandatory=$false)]  [Alias('t')] [AllowNull()] [Nullable[System.DateTime]] $To,
	[Parameter(Mandatory=$false)]  [Alias('l')] [AllowNull()] [Nullable[System.Int32]] $LastDays,
	[Parameter(Mandatory=$false)]  [Alias('m')] [AllowNull()] [Nullable[System.Int32]] $MaxCommits = 10
	)

# Create the authorization header
$encodedCredentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(":"+$Pat))
$headers = @{
    Authorization = "Basic $encodedCredentials"
}

if ($LastDays -ne $null -and $From -eq $null) {
	$From = [System.DateTime]::Now.AddDays(-$LastDays)
}

if ($Repositories -eq $null) {
	echo $Pat | az devops login
	$repos = (az repos list --organization "https://dev.azure.com/$Organization" --project $Project) | ConvertFrom-Json
	$Repositories = $repos.name
}	
	
foreach ($repo in $Repositories) {
	$queryUrl = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories/$repo/commits?searchCriteria.author=$User"

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
			Write-Host "$($commit.author.date) $($commit.comment) [$($commit.commitId)]"	
		}
	}
}
