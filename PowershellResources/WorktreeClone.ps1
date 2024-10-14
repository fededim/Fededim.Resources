<#
.SYNOPSIS

Utility to work with multiple releases of one or more GIT repositories using clone/worktrees. 
For every branch a local folder with a modified branch name (all slashes and backslashes will be replaced with underscore) will be created and every repository will be cloned/updated there in a subfolder (the last part of the repository url without ".git").
main and master branches will be cloned, all other branches will be created as git worktrees.

.DESCRIPTION

You must specify the GIT repositories (in $Repositories) and the branch name (in $Branch) which must be cloned or updated to the latest commit.

.PARAMETER Branch
Specifies the branch of all repositories which must be cloned 

.PARAMETER Repositories
Specifies an array of repositories to clone or update, e.g. @("https://github.com/fededim/Fededim.Resources.git","https://github.com/fededim/Fededim.Extensions.Configuration.Protected.git")

.INPUTS

None.

.OUTPUTS

None

.EXAMPLE

PS> WorktreeClone -Repositories @("https://github.com/fededim/Fededim.Resources.git","https://github.com/fededim/Fededim.Extensions.Configuration.Protected.git")

- A local folder "master" or "main" will be created according to each remote repository default branch
- Each repository default branch will be cloned/updated into a subfolder inside the corresponding master/main one

PS> WorktreeClone develop @("https://github.com/fededim/Fededim.Resources.git","https://github.com/fededim/Fededim.Extensions.Configuration.Protected.git")

- If the master/main branch of a repository is not present inside the respective folder (master/main) it will be cloned
- A local folder "develop" will be created
- Inside develop folder any repository with the branch "develop" will be cloned/updated into the respective subfolder

PS> WorktreeClone release/2.0 @("https://github.com/fededim/Fededim.Resources.git","https://github.com/fededim/Fededim.Extensions.Configuration.Protected.git")

- If the master/main branch of each repositories is not present inside the respective folder (master/main) it will be cloned
- A local folder "release_2.0" will be created
- Inside release_2.0 folder any repository with the branch "release/2.0" will be cloned/updated into the respective subfolder
 

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2024 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory=$false)]  [Alias('b')] [String] $Branch,
	[Parameter(Mandatory=$false)]  [Alias('r')] [String[]] $Repositories
	)


function IIf {
	Param (
	[Parameter(Mandatory=$true)] [System.Boolean] $booleanExpression,
	[Parameter(Mandatory=$false)] $TrueExpression,
	[Parameter(Mandatory=$false)] $FalseExpression
	)

	if ($booleanExpression) { ,$TrueExpression } else { ,$FalseExpression }
}


$masterBranches = @("master","main")


if ($Repositories -eq $null) {
	$Repositories = @("https://github.com/fededim/Fededim.Resources.git","https://github.com/fededim/Fededim.Extensions.Configuration.Protected.git","https://github.com/fededim/BinaryToPowershellScript.git")
}


$IsBranchEmpty = [System.String]::IsNullOrEmpty($Branch)

foreach ($repository in $Repositories) {
	if ($IsBranchEmpty) {
		$Branch = (Split-Path ([Regex]::Matches((git ls-remote --symref $repository),"ref:\s+(\S+)\s+HEAD").Groups[1].Value) -Leaf)
	}

	$branchFolderName = IIf ($masterBranches -contains $Branch) $Branch $($Branch -replace '[\/\\]','_')
	[void](New-Item -ItemType Directory -Force -Path $branchFolderName)
	cd $branchFolderName

	$repositoryName = $(Split-Path $repository -Leaf).Replace(".git",[System.String]::Empty);
	if (Test-Path -PathType Any "$repositoryName\.git") {
		# git repository exists
		cd $repositoryName
		Write-Host "`nUpdating existing REPOSITORY $repositoryName BRANCH $Branch FOLDER $(Get-Location)"
		git checkout $Branch
		git pull
		cd ..
	}
	else {
		# git repository does not exist
		if ($masterBranches -contains $Branch) {
			Write-Host "`nCloning REPOSITORY $repositoryName BRANCH $Branch FOLDER $(Get-Location)\$repositoryName"
			git clone -b $Branch "$repository"
		}
		else {
			Remove-Item -Path $repositoryName -Recurse -Force -ErrorAction SilentlyContinue
			[void](New-Item -ItemType Directory -Force -Path $repositoryName)

			if (Test-Path -Path "..\master\$repositoryName") {
				cd "..\master\$repositoryName"
			}
			elseif (Test-Path -Path "..\main\$repositoryName") {
				cd "..\main\$repositoryName"
			}
			else {
				$remoteMasterBranchName = (Split-Path ([Regex]::Matches((git ls-remote --symref $repository),"ref:\s+(\S+)\s+HEAD").Groups[1].Value) -Leaf)
				[void](New-Item -ItemType Directory -Force -Path "..\$remoteMasterBranchName")
				cd "..\$remoteMasterBranchName"
				Write-Host "`nCloning REPOSITORY $repositoryName BRANCH $remoteMasterBranchName FOLDER $(Get-Location)"
				git clone "$repository"
				cd "$repositoryName"
			}

			Write-Host "`nAdding worktree REPOSITORY $repositoryName BRANCH $Branch FOLDER $(Get-Location)"
			git worktree add -f "..\..\$branchFolderName\$repositoryName" "$Branch"
			cd "..\..\$branchFolderName"

			# remove repository folder if the branch does not exist
			if (-Not (Test-Path -Path "$repositoryName\*")) {
				Write-Host "REPOSITORY $repositoryName is empty, probably BRANCH $Branch does not exist, deleting folder.."
				Remove-Item -Path $repositoryName -Recurse -Force -ErrorAction SilentlyContinue
			}
		}
	}

	cd ..
}

# remove branch folder if it is empty
if (-Not (Test-Path -Path "$branchFolderName\*")) {
	Write-Host "`nFOLDER $branchFolderName is empty, BRANCH $Branch does not exist in any repository, deleting folder.."
	Remove-Item -Path $branchFolderName -Recurse -Force -ErrorAction SilentlyContinue
}
