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

.PARAMETER SkipPullRequestCommits
If set,it does not display pull request commits (e.g. those starting with the pattern "Merge*")

.INPUTS

None.

.OUTPUTS

A list of user commits matching the above parameters. The returned information contains:
- Commit date
- Commit comment
- Commit hash or a hyperlink to commit if you use Windows Terminal

.EXAMPLE

PS> AzureDevopsQueryUserCommits -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token>

- Returns the last 10 commits from all repositories inside the organization among all branches

PS> AzureDevopsQueryUserCommits -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token> -To "2024-06-01T12:56:34" -MaxCommits 50

- Returns the last 50 commits from all repositories inside the organization among all branches done before 1 June 2024, 12:56:34

PS> AzureDevopsQueryUserCommits -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token> -From "2024-06-01T12:56:34" -MaxCommits 15

- Returns the first 15 commits from all repositories inside the organization among all branches done after 1 June 2024, 12:56:34

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2024 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()]  [Alias('u')] [String] $User,
	[ValidateNotNullOrEmpty()]  [Alias('a')] [String] $Pat,
	[ValidateNotNullOrEmpty()]  [Alias('o')] [String] $Organization,
	[ValidateNotNullOrEmpty()]  [Alias('p')] [String] $Project,
	[Parameter(Mandatory=$false)]  [Alias('r')] [String[]] $Repositories,
	[Parameter(Mandatory=$false)]  [Alias('f')] [AllowNull()] [Nullable[System.DateTime]] $From,
	[Parameter(Mandatory=$false)]  [Alias('t')] [AllowNull()] [Nullable[System.DateTime]] $To,
	[Parameter(Mandatory=$false)]  [Alias('l')] [AllowNull()] [Nullable[System.Int32]] $LastDays,
	[Parameter(Mandatory=$false)]  [Alias('mc')] [AllowNull()] [Nullable[System.Int32]] $MaxCommits = 20,
	[Parameter(Mandatory=$false)]  [Alias('spr')] [switch] $SkipPullRequestCommits=$false
	)

$hyperlinksSupported = ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) -and $Env:WT_SESSION

# code partly borrowed from https://lucyllewy.com/powershell-clickable-hyperlinks/
function Format-Hyperlink {
  param(
    [Parameter(ValueFromPipeline = $true)] [ValidateNotNullOrEmpty()] [Uri] $Uri,
    [Parameter(Mandatory=$false)] [string] $Label
	)
	
	if ($hyperlinksSupported -eq $True) {
		return "`e]8;;$Uri`e\$Label`e]8;;`e\"
	}
	else {
		return "$Uri"
	}
}


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
	$queryUrl = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories/$repo/commits?searchCriteria.committer=$User&searchCriteria.includePushData=true&searchCriteria.includeWorkItems=true"

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
			if ($SkipPullRequestCommits -eq $false -or $($commit.comment) -notlike "Merge*") {
				Write-Host "$($commit.committer.date): $($commit.comment) [$(Format-Hyperlink -Uri $($commit.remoteUrl) -Label $($commit.commitId))]"
			}
		}
	}
}
