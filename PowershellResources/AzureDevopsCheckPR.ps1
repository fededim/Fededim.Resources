<#
.SYNOPSIS

Utility to report the status of pull requests created by a user using Azure Devops REST API.

If a PR has an expired build, it is requeued automatically.

If the switch IntegrateRejectedBuilds is set, the pull request source branch is automatically integrated with the latest origin target branch changes.

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

.PARAMETER IntegrateRejectedBuilds
If set, all pull requests whose build status is rejected are automatically integrated with the latest origin target branch changes.
If this operation fails for any reasons (e.g. conflicts or whatever), it is rollbacked and the script is printed at the end for manual integration.

.PARAMETER GenerateIntegrationScriptForRejectedBuilds
If set, all the integration scripts for failed builds are printed at the end for manual integration

.PARAMETER ForceRequeueRejectedBuilds
If set, all pull requests whose build status is rejected are automatically requeued notwithstanding the time elapsed from last run.

.INPUTS

None.

.OUTPUTS

A list of pull requests created by the user which require attention. The returned information contains:
- Pull request url
- One or more statuses inside square brackets

There is one row for each pull request whose color is:
- Green: if the attention has been solved automatically (build expired --> build has been requeued)
- Gray: if the status of pull request is still undertermined because the build is ongoing or has not started yet. 
- Red: if the pull request needs manual intervention (builds fails, comments must be resolved, etc.)

.EXAMPLE

PS> AzureDevopsCheckPR -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token>

- Returns the list of pull requests requiring attention

PS> AzureDevopsCheckPR -User <Azure Devops user email> -Organization <organization> -Project <project> -Pat <personal access token> -LocalGitFolder "C:\Users\<user>\source\repos" -IntegrateRejectedBuilds

- Returns the list of pull requests requiring attention and automatically integrates the pull request source branch with the latest origin target branch changes.

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2024 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()] [Alias('u')] [String] $User,
	[ValidateNotNullOrEmpty()] [Alias('a')] [String] $Pat,
	[ValidateNotNullOrEmpty()] [Alias('o')] [String] $Organization,
	[ValidateNotNullOrEmpty()] [Alias('p')] [String] $Project,
	[ValidateNotNullOrEmpty()] [Alias('lgf')] [String] $LocalGitFolder=".",
	[ValidateNotNullOrEmpty()] [Alias('i')] [switch] $IntegrateRejectedBuilds=$false,
	[ValidateNotNullOrEmpty()] [Alias('gsrb')] [switch] $GenerateIntegrationScriptForRejectedBuilds=$false,
	[ValidateNotNullOrEmpty()] [Alias('fr')] [switch] $ForceRequeueRejectedBuilds=$false,
	[Parameter(Mandatory=$false)] [Alias('bm')] [ScriptBlock] $BranchMappings
	)


# This function is a custom datetime parsing function which tries to parse the date with all possible datetime formats 
# (with days and seconds) of all system cultures. It was used temporarily because there was a bug on completed date, 
# now it is not used anymore, I still keep it for now, after thorough testing I will remove it
function ParseDateTime {
  param(
    [Parameter(ValueFromPipeline = $true)] [ValidateNotNullOrEmpty()] [String] $DateTimeString
	)
	
	$parsedDate = [System.Datetime]::Now
	
	# try the standard way
	if ([System.Datetime]::TryParse($DateTimeString, [ref]$parsedDate) -eq $true) {
		return $parsedDate
	}

	# try everything else
	foreach ($cultureInfo in [System.Globalization.CultureInfo]::GetCultures([System.Globalization.CultureTypes]::AllCultures)) {
		foreach ($dateTimePattern in $cultureInfo.DateTimeFormat.GetAllDateTimePatterns()) {
			if ($dateTimePattern -like "*dd*ss*") {
				if ([System.DateTime]::TryParseExact($DateTimeString, $dateTimePattern, $cultureInfo, [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate) -eq $true) {
					return $parsedDate
				}
			}
		}
	}

	return $null
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
		}
	}
}


echo $Pat | az devops login

$userPullRequests = (az repos pr list --organization "https://dev.azure.com/$Organization" --project $Project --creator $User) | ConvertFrom-Json


$rejectedBuildIntegrationScript = ""

Write-Host "Pull requests requiring attention`n---------------------------------`n"
foreach ($userPull in $userPullRequests) {
	$evaluations = (az repos pr policy list --organization "https://dev.azure.com/$Organization" --id $($userPull.pullRequestId)) | ConvertFrom-Json

	$action = @{ color = $([System.Console]::ForegroundColor)
				 text = "" }
	foreach ($evaluation in $evaluations) {
		# Build policy management
		if ($($evaluation.configuration.type.displayName) -eq "Build") {
			# If rejected
			if ($($evaluation.status) -eq "rejected") {
				# If completed less than 2 hours, retry with another build
				if ((([System.DateTime]::Now.Subtract($($evaluation.completedDate))) -le (New-TimeSpan -minutes 120)) -or ($ForceRequeueRejectedBuilds -eq $True)) {		
					az repos pr policy queue --organization "https://dev.azure.com/$Organization" --id $($userPull.pullRequestId) --evaluation-id $evaluation.evaluationId | Out-Null
					$action.text = $action.text + "Build:rejected-requeued / "
					$action.color = 'Green'
					continue	
				}
				elseif ($IntegrateRejectedBuilds -eq $True -or $GenerateIntegrationScriptForRejectedBuilds -eq $True) {
					# otherwise perform a target branch changes integration
					$originBranch = $($userPull.sourceRefName) -replace "refs/heads/",""
					$targetBranch = $($userPull.targetRefName) -replace "refs/heads/",""

					$targetBranchFolder = (Invoke-Command -ScriptBlock $BranchMappings -ArgumentList "ToFolder",$LocalGitFolder,$originBranch,$targetBranch,$targetBranch)
					
					$script = "# $($userPull.title) https://dev.azure.com/$Organization/$Project/_git/$($userPull.repository.name)/pullrequest/$($userPull.pullRequestId)`n`n"
					$script = $script + "cd $targetBranchFolder\$($userPull.repository.name)`n"
					$script = $script + "git fetch`ngit checkout $originBranch`ngit merge origin/$targetBranch --commit --no-edit`nif (`$?) {`n`tgit push`n}`nelse {`n`tgit merge --abort`n`tgit restore .`n`tthrow `"merge error`"`n}`n`n`n"

					if ($GenerateIntegrationScriptForRejectedBuilds -eq $False) {
						powershell -Command $script >$null 2>&1
					}

					else {
						powershell -Command "exit 2"
					}

					if ($? -eq $True) {
						# if target branch changes integration completed successfully
						$action.text = $action.text + "Build:integrated-origin / "
						$action.color = 'Green'
						continue
					}
					else {
						# if target branch changes integration does not work for any reason store the script in order to output it at the end for troubleshooting
						$rejectedBuildIntegrationScript = $rejectedBuildIntegrationScript + $script				
					}
				}
			}
			# If expired requeue it
			elseif ($($evaluation.context.isExpired) -eq $true) {
				az repos pr policy queue --organization "https://dev.azure.com/$Organization" --id $($userPull.pullRequestId) --evaluation-id $evaluation.evaluationId | Out-Null
				$action.text = $action.text + "Build:expired-requeued / "
				$action.color = 'Green'
				continue
			}
		}
		
		# other policy management, if it is not approved and does not regard reviewers, report it, in console default color if not decided yet (e.g. queued or running) otherwise in red color
		if (($($evaluation.configuration.type.displayName) -notlike "*reviewers*") -and ($($evaluation.status) -ne "approved")) {
			$action.text = $action.text + "$($evaluation.configuration.type.displayName):$($evaluation.status) / "			
			if ($($evaluation.status) -ne "queued" -and $($evaluation.status) -ne "running") {
				$action.color = 'Red'
			}
		}
	}


	if ($($userPull.mergeStatus) -ne "succeeded") {
		$action.text = $action.text + "Merge:$($userPull.mergeStatus) / " 
		$action.color = 'Red'
	}
	
	# log pull request status if there is something which needs attention
	if (![System.String]::IsNullOrEmpty($($action.text))) {
		Write-Host "https://dev.azure.com/$Organization/$Project/_git/$($userPull.repository.name)/pullrequest/$($userPull.pullRequestId) [$($action.text)]" -ForegroundColor $action.color
	}
}

# output all failed target branch changes integrations for troubleshooting
if (![System.String]::IsNullOrEmpty($rejectedBuildIntegrationScript)) {
	Write-Host "`nOrigin integration failed scripts`n---------------------`n$rejectedBuildIntegrationScript"
}
