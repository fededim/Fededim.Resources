<#
.SYNOPSIS

Utility to execute test multiple times a .NET application, storing all outputs (TRX file and HTML report) in a specified output folder, creating also a ZIP archive.

.DESCRIPTION

This script must be copied into the folder of the test project, which must be based on Microsoft.Testing.Platform (MTP) framework. The test project is rebuilt automatically before testing.

.PARAMETER Iterations
Specifies the number of times the tests needs to be launched

.PARAMETER Configuration
Specifies the configuration Debug or Release. Defaults to release

.PARAMETER OutputFolder
Specifies the output folder where the test results (TRX file and HTML report) will be saved.

.PARAMETER Frameworks
Specifies an array of the frameworks which needs to be tested, this is necessary due to a XUnit V3 unresolved bug https://github.com/xunit/xunit/issues/864

.INPUTS

None.

.OUTPUTS

None

.EXAMPLE

PS> MultipleDotnetTests -i 10 -o "c:\temp" -f @("net10.0","net48")

Executes the tests 10 times, saving all output file in c:\temp

PS> MultipleDotnetTests -i 10 -o "c:\temp" -c Debug -f @("net10.0","net48")

Executes the tests 10 times, saving all output file in c:\temp, compiling in debug mode.

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2026 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param (
    [ValidateNotNullOrEmpty()] [Alias('i')] [int] $Iterations = 3,
    [ValidateNotNullOrEmpty()] [Alias('c')] [String] $Configuration = "Release",
    [ValidateNotNullOrEmpty()] [Alias('o')] [String] $OutputFolder = "./TestResults",
    [ValidateNotNullOrEmpty()] [Alias('o')] [String[]] $Frameworks = @("net48","net10.0")
)

$Timestamp = (Get-Date -Format "ddMMyyyyHHmmss")
$ProjectName = $(Get-Item $PSScriptRoot).Name
$OutputDir = "$($ProjectName)_$($Iterations)-Runs_$($Timestamp)"
$OutputDirectory = Join-Path $OutputFolder $OutputDir
#$MergedFileName = Join-Path $OutputDirectory "Cumulative_Result.trx"
$OutputArchive = Join-Path $OutputFolder "$($OutputDir).zip"

Write-Host "=== Starting multiple retries test ($Iterations iterations) ===" -ForegroundColor Cyan

Write-Host "`n`ProjectName: $ProjectName" -ForegroundColor DarkGreen
Write-Host "Output Directory: $OutputDirectory" -ForegroundColor DarkGreen

[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

dotnet clean
dotnet build -c $Configuration

for ($i = 1; $i -le $Iterations; $i++) {
    Write-Host "-> Executing test $i of $Iterations..." -ForegroundColor Green
    
    # split test separately using --framework option, because launching dotnet test without it went into a deadlock after a few hundred tests
    # there is even a bug on GitHub https://github.com/xunit/xunit/issues/864 which has been closed, attributing the culprit to async / await code in the tests
    # unfortunately none of this code uses any async or await, except for a global mutex, which is perfect :-) Probably it will be reopened and fixed in the fixture
	foreach ($framework in $Frameworks) {
		dotnet test -c "$Configuration" --framework "$framework" --results-directory "$OutputDirectory" -- --report-trx --report-trx-filename "{tfm}-{arch}\testrun_$i.trx" --report-html --report-html-filename "{tfm}-{arch}\testrun_$i.html"
	}
}

Compress-Archive -Path "$OutputDirectory" -DestinationPath "$OutputArchive" -CompressionLevel Optimal
Write-Host "[SUCCESS] All test output files have been archived into: $OutputArchive" -ForegroundColor Cyan
