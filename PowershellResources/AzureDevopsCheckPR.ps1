[CmdletBinding()]
param(
	[Parameter(Mandatory=$false)]  [Alias('u')] [String] $User = "<azure devops user email>"
	)


$pat = "<personal access token>"
$organization = "https://dev.azure.com/<organization>"
$project = "<project>"

echo $pat | az devops login

$userPullRequests = (az repos pr list --organization $organization --project $project --creator $User) | ConvertFrom-Json

$invalidPullRequests = $userPullRequests | Where-Object { $_.mergeStatus -ne "succeeded" }

Write-Host "Invalid pull requests`n---------------------`n"

foreach ($userPull in $invalidPullRequests) {
	Write-Host "$organization/$project/_git/$($userPull.repository.name)/pullrequest/$($userPull.pullRequestId)"
}
