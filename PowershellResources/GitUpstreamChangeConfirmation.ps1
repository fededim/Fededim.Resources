<#
.SYNOPSIS

Utility which sets up a confirmation whenever you push changes to a changed upstream repository.

.DESCRIPTION

It creates a GitHook with a small bash script which asks for confirmation whenever you push to a changed upstream repository.

.PARAMETER Local
Specifies to create the GitHook only for the local git repository. By default it is false, so the GitHook is created globally in the user home directory for all repositories.

.INPUTS

None.

.OUTPUTS

None.

.EXAMPLE

PS> GitUpstreamChangeConfirmation.ps1 

Sets us a global confirmation for all Git repositories of the current user

PS> GitUpstreamChangeConfirmation.ps1 -Local

Sets us a local confirmation only for the local Git repository of the current folder

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2026 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
    param (
        [switch]$Local
    )

    # 1. Define the Bash content for the hook
    $scriptContent = @'
#!/bin/bash

# Fetch the latest remote state quietly before evaluating
git fetch --quiet

# Grab the current local and upstream commits
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u} 2>/dev/null)

# If there is no remote tracking branch set up yet, allow the push safely
if [ -z "$REMOTE" ]; then
    exit 0
fi

BASE=$(git merge-base HEAD @{u})

# Check if the upstream has moved ahead of your branch
if [ "$LOCAL" != "$REMOTE" ] && [ "$LOCAL" = "$BASE" ]; then
    echo "=========================================================="
    echo "⚠️  WARNING: The upstream repository has changed! You are behind."
    echo "=========================================================="
    
    # Re-route the input stream to read directly from the user's TTY console
    exec < /dev/tty
    read -p "Do you still want to proceed with this push? (y/N): " yn
    case $yn in
        [Yy]* ) 
            echo "Proceeding with push..."
            exit 0
            ;;
        * ) 
            echo "❌ Push aborted by user."
            exit 1
            ;;
    esac
fi

exit 0
'@

    # 2. Determine target path based on user choice
    if ($Local) {
        # Verify that we are at the root of a Git repository
        if (-not (Test-Path ".git")) {
            Write-Error "Error: Current directory is not a Git repository root. Cannot find '.git' folder."
            return
        }
        $targetDir = Join-Path (Get-Item ".").FullName ".git\hooks"
    } 
    else {
        # Set up global path environment
        $targetDir = Join-Path $HOME ".git-hooks"
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir | Out-Null
        }
    }

    $hookFile = Join-Path $targetDir "pre-push"

    # 3. Backup Feature: Check if a pre-push hook already exists
    if (Test-Path $hookFile) {
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $backupFile = "${hookFile}_backup_${timestamp}"
        
        try {
            Copy-Item -Path $hookFile -Destination $backupFile -Force
            Write-Host "📦 Backup Created: An existing 'pre-push' hook was found and backed up to: `n   $backupFile" -ForegroundColor Yellow
        } catch {
            Write-Error "Failed to create a backup file. Aborting execution to prevent data loss."
            return
        }
    }

    # 4. Write the hook using explicit UTF-8 encoding (without a BOM) for Git Bash compatibility
    try {
        [System.IO.File]::WriteAllLines($hookFile, $scriptContent)
        
        if ($Local) {
            Write-Host "✅ Created LOCAL pre-push hook script at: $hookFile" -ForegroundColor Green
        } else {
            # Update global config only if it's the global route
            git config --global core.hooksPath "$HOME/.git-hooks"
            Write-Host "✅ Created GLOBAL pre-push hook script at: $hookFile" -ForegroundColor Green
            Write-Host "🌐 Git global configuration updated! Confirmation is now active machine-wide." -ForegroundColor Cyan
        }
    } catch {
        Write-Error "Failed to write the hook file: $_"
    }