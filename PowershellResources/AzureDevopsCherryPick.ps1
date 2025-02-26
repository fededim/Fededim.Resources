<#
.SYNOPSIS

Utility to perform a whole pull request cherry pick using Azure Devops REST API
(to be used when Azure Devops built-in cherry-pick menu function fails).

.DESCRIPTION

You must specify the Azure Devops user email (in $User), the organization (in $Organization), the project (in $Project) and a personal access token (in $Pat)

.PARAMETER User
Specifies the user email whose commits will be listed.

.PARAMETER Pat
Specifies the personal access token with identity (read) and code (read and status) permissions.

.PARAMETER Organization
Specifies the Azure Devops organization

.PARAMETER Project
Specifies the Azure Devops project

.PARAMETER LocalGitFolder
Specifies the local folder used to the git repositories, used when enabling IntegrateRejectedBuilds switch

.PARAMETER PullRequestId
Pull Request id to cherry-pick

.PARAMETER DestinationBranches
The destination branches in ascending order (from the minor version up to the latest one) towards which the whole PullRequestId must be cherry-picked
	
.PARAMETER BranchMappings
This is a Powershell "function pointer" which is used to inject your own naming convention, if you do not like the default one. Essentially you have to define a scriptblock (e.g. a function) which takes in input these 5 parameters

param([String] $ConversionType,
	  [String] $LocalGitFolder,
	  [String] $PullRequestSourceBranch,
	  [String] $PullRequestTargetBranch,
	  [String] $TargetBranch)

and according $ConversionType input parameter it should return a string with the requested naming. Two naming conventions are mandatory:
- "ToFolder" for converting the $TargetBranch to a file system folder where the git repository is located
- "ToCherrypickBranch" for converting the $PullRequestSourceBranch to the cherry-pick branch targeting the $TargetBranch (usually release/xx)

.INPUTS

None.

.OUTPUTS

A series of powershell scripts which create a new branch and perform the cherry pick 

.EXAMPLE

PS> CherryPick.ps1 -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token> -LocalGitFolder "C:\Users\<user>\source\repos\" -DestinationBranches @("release/1.0","release/1.5","release/2.0","master") -PullRequest 12345

- Returns the series of powershell scripts

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2025 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()] [Alias('u')] [String] $User,
	[ValidateNotNullOrEmpty()] [Alias('a')] [String] $Pat,
	[ValidateNotNullOrEmpty()] [Alias('o')] [String] $Organization,
	[ValidateNotNullOrEmpty()] [Alias('p')] [String] $Project,
	[ValidateNotNullOrEmpty()] [Alias('f')] [String] $LocalGitFolder=".",
	[ValidateNotNullOrEmpty()] [Alias('pr')] [Nullable[System.Int32]] $PullRequestId,
	[ValidateNotNullOrEmpty()] [Alias('b')] [String[]] $DestinationBranches,
	[Parameter(Mandatory=$false)] [Alias('bm')] [ScriptBlock] $BranchMappings
	)

echo $Pat | az devops login

# Create the authorization header
$encodedCredentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(":"+$Pat))
$headers = @{
    Authorization = "Basic $encodedCredentials"
}

if ($BranchMappings -eq $null) {
	[scriptblock]$BranchMappings = {
		param([String] $ConversionType,
			  [String] $LocalGitFolder,
			  [String] $PullRequestSourceBranch,
			  [String] $PullRequestTargetBranch,
			  [String] $TargetBranch)
		
		switch($ConversionType) {
			"ToFolder" {
				return "$LocalGitFolder\$(Split-Path $TargetBranch -Leaf)"
				break;
			}
			
			"ToCherrypickBranch" {
				return ($PullRequestSourceBranch -replace 'release/','') -replace (Split-Path $PullRequestTargetBranch -Leaf),($TargetBranch -replace 'release/','')
				break;
			}
		}
	}
}

$pullRequest = (az repos pr show --organization "https://dev.azure.com/$Organization" --id $PullRequestId) | ConvertFrom-Json

$workItemsIds = $($pullRequest.workItemRefs.id) -join ' '

$commits = (Invoke-RestMethod -Uri "https://dev.azure.com/$Organization/$Project/_apis/git/repositories/$($pullRequest.repository.name)/pullRequests/$($pullRequest.pullRequestId)/commits?api-version=7.1" -Headers $headers -Method Get).value
[Array]::Reverse($commits)

$originBranch = $($pullRequest.sourceRefName) -replace 'refs/heads/',''
$targetBranch = $($pullRequest.targetRefName) -replace 'refs/heads/',''

$startIndex = [Math]::Max($DestinationBranches.IndexOf($targetBranch)+1,0)

Write-Host "Cherrypicking`n-------------`n" -ForegroundColor Green
for ($i = $startIndex; $i -lt $DestinationBranches.Length; $i++) {
	$branch = $DestinationBranches[$i]

	# Write-Host "Analyzing PullReq $($pullRequest.title) https://dev.azure.com/$Organization/$Project/_git/$($pullRequest.repository.name)/pullrequest/$($pullRequest.pullRequestId)`n`n" 
	
	$cherrypickBranchFolder = (Invoke-Command -ScriptBlock $BranchMappings -ArgumentList "ToFolder",$LocalGitFolder,$originBranch,$targetBranch,$branch)
	$cherryPickBranch = (Invoke-Command -ScriptBlock $BranchMappings -ArgumentList "ToCherrypickBranch",$LocalGitFolder,$originBranch,$targetBranch,$branch)
	
	Write-Host "PullReq $($pullRequest.pullRequestId) [$($pullRequest.title)]`nPR source branch $originBranch target $branch --> cherrypick $cherryPickBranch`n`n" -ForegroundColor Green

	$script = "# PR #$($pullRequest.pullRequestId) [$($pullRequest.title)]: https://dev.azure.com/$Organization/$Project/_git/$($pullRequest.repository.name)/pullrequest/$($pullRequest.pullRequestId)`n"
	$script = $script +"# Source branch $originBranch`n"
	$script = $script +"# Cherrypicking to $branch creating a new branch $cherryPickBranch`n`n"
	$script = $script + "cd $cherrypickBranchFolder\$($pullRequest.repository.name)`n"
	$script = $script + "git fetch`ngit checkout $branch`ngit pull`ngit checkout -b $cherryPickBranch`n`$cherrypicks = @("
	

	foreach ($commit in $commits) {
		$script = $script + "`"git cherry-pick $($commit.commitId) # $($commit.comment)`","
	}

	$script = $script + "`"git push -u origin $cherryPickBranch`","
	$script = $script + "`"az repos pr create --organization ```"https://dev.azure.com/$Organization```" --project ```"$Project```" --repository ```"$($pullRequest.repository.name)```" --title ```"$($pullRequest.title)```" --description ```"$($pullRequest.description)```" --work-items ```"$workItemsIds```" --auto-complete true --squash true --delete-source-branch true --source-branch ```"$cherryPickBranch```" --target-branch ```"$branch```"`")`n`n"

	$script = $script + "`$i=0`nfor (;`$i -lt `$cherrypicks.Length; `$i++) {`n`tpowershell -Command `$cherrypicks[`$i]`n`tif (`$? -eq `$false) {`n`t`tWrite-Host `"Error while cherry-picking ```"`$(`$cherrypicks[`$i])```"`"`n`t`tbreak`n`t}`n}`n`n"
	$script = $script + "for (`$j=`$i;`$j -lt `$cherrypicks.Length; `$j++) {`n`tWrite-Host `$cherrypicks[`$j]`n}`n`n"

	Write-Host "$script"
}
