<#
.SYNOPSIS

Utility to test the speed of a local web server

.DESCRIPTION

Utility to test the speed of a local web server, by performing multiple GET requests and calculating the minimum, maximum and average times for the different phases:
- time_namelookup: the DNS lookup time
- time_connect: the moment when the TCP connection is established
- time_appconnect: the moment when the TLS tunnel is established
- time_redirect: the moment when all redirection steps ends
- time_pretransfer: the moment when the web server starts processing the request
- time_starttransfer: the moment when the first byte of the response is returned
- time_total: the total elapsed time of the request


.PARAMETER $Uri
Specifies the http / https url to download with a GET request

.PARAMETER $LocalIp
Specifies a local ip address which is automatically used replacing the original DNS resolved ip

.PARAMETER $Times
Specifies the number of time the request is performed

.PARAMETER $NoRevoke
Specifies a flag to disables TLS certificate revocation checks

.INPUTS

None.

.OUTPUTS

Statistics on each phase of the request calculating, minimum, maximum and average

.EXAMPLE

PS> LanSpeed.ps1

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2026 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()] [Alias('u')] [String] $Uri,
    [ValidateNotNullOrEmpty()] [Alias('l')] [String] $LocalIp = '172.19.1.201',
    [ValidateRange(1, 1000)] [Alias('t')] [Int] $Times = 1,
    [switch] [Alias('r')] $NoRevoke
)

# Numeric timing keys that need conversion to ms
$timeKeys = @(
    "time_namelookup", 
    "time_connect", 
    "time_appconnect", 
    "time_pretransfer", 
    "time_redirect", 
    "time_starttransfer", 
    "time_total"
)

# Extra metadata keys
$metaKeys = @(
    "remote_ip",
    "remote_port",
    "size_header",
    "size_download"
)

# Combine keys for curl format configuration
$allKeys = $timeKeys + $metaKeys
$customFormat = ($allKeys | ForEach-Object { "[${_}:%{${_}}]" }) -join ""

# Storage for results across all iterations
$allRuns = @()

Write-Host "Executing $Times iteration(s)..." -ForegroundColor Cyan

for ($i = 1; $i -le $Times; $i++) {
    # Prepare curl arguments array
    $curlArgs = @(
        "-w", $customFormat,
        "-s",
        "-o", "NUL",
        "--resolve", "*:443:$LocalIp"
        "--resolve", "*:80:$LocalIp"
    )
    if ($NoRevoke) { $curlArgs += "--ssl-no-revoke" }
    $curlArgs += $Uri

    # Execute curl natively
    $output = & curl.exe @curlArgs

    # Parse out the key/value pairs using regex
    $runMetrics = [ordered]@{ "Iteration" = $i }
    foreach ($key in $allKeys) {
        $pattern = "\[${key}:([^\]]+)\]"
        if ($output -match $pattern) {
            $val = $matches[1].Trim()
            if ($timeKeys -contains $key -or $key -like "size*") {
                # Parse numeric values safely using InvariantCulture
                $runMetrics[$key] = [double]::Parse($val, [System.Globalization.CultureInfo]::InvariantCulture)
            } else {
                $runMetrics[$key] = $val
            }
        } else {
            $runMetrics[$key] = if ($timeKeys -contains $key -or $key -like "size*") { 0.0 } else { "" }
        }
    }
    
    $allRuns += [PSCustomObject]$runMetrics
}

# If only 1 run was requested, print a clean list view
if ($Times -eq 1) {
    $singleRunTable = [ordered]@{}
    foreach ($key in $timeKeys) {
        $singleRunTable[$key] = "{0:F2} ms" -f ($allRuns.$key * 1000)
    }
    foreach ($key in $metaKeys) {
        if ($key -like "size*") {
            $singleRunTable[$key] = "{0:N0} bytes" -f $allRuns.$key
        } else {
            $singleRunTable[$key] = $allRuns.$key
        }
    }
    [PSCustomObject]$singleRunTable | Format-List
} 
else {
    # Construct rows where keys are properties, displaying columns for Min, Avg, Max
    $rows = @()
    
    foreach ($key in $timeKeys) {
        $stats = $allRuns | Measure-Object -Property $key -Minimum -Maximum -Average
        $rows += [PSCustomObject]@{
            Metric  = $key
            Minimum = "{0:F2} ms" -f ($stats.Minimum * 1000)
            Average = "{0:F2} ms" -f ($stats.Average * 1000)
            Maximum = "{0:F2} ms" -f ($stats.Maximum * 1000)
        }
    }

    # Add metadata entries as rows (static values across runs)
    $lastRun = $allRuns[-1]
    foreach ($key in $metaKeys) {
        $valStr = if ($key -like "size*") { "{0:N0} bytes" -f $lastRun.$key } else { $lastRun.$key }
        $rows += [PSCustomObject]@{
            Metric  = $key
            Minimum = $valStr
            Average = $valStr
            Maximum = $valStr
        }
    }

    Write-Host "`n=== BENCHMARK SUMMARY OVER $Times ITERATIONS ===" -ForegroundColor Green
    $rows | Format-Table -Property Metric, Minimum, Average, Maximum
}