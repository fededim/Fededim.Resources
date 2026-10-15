<#
.SYNOPSIS

Utility to test the speed of a local web server

.DESCRIPTION

Utility to test the speed of a local web server, by performing multiple GET requests and calculating the minimum, maximum and average times for the different phases.
For each phase the output shows its DURATION (the difference with the previous phase) followed by, in parenthesis, the time elapsed from the start of the request until the phase starts (the end time of the previous phase as reported by curl, 0 for the first phase).
The only exception is time_total, which is shown as its raw value (the total elapsed time), without any difference with the previous phase.
- time_namelookup: the DNS lookup time (alias: DNS Lookup)
- time_connect: the moment when the TCP connection is established (alias: TCP Connect)
- time_appconnect: the moment when the TLS tunnel is established, n/a for plain http (alias: TLS Tunnel)
- time_pretransfer: the moment when the request is about to be sent to the web server (alias: Sending Request)
- time_starttransfer: the moment when the first byte of the response is returned, its duration is the server processing time (alias: Server Processing)
- time_download (derived): the time spent downloading the response body, time_total - time_starttransfer (alias: Response Download)
- time_total: the total elapsed time of the request, raw value (alias: Elapsed Time)
- time_redirect: the total time spent in redirection steps, already a duration, not a point in time (alias: Redirect Overhead)
- remote_ip: the IP address of the server (alias: Remote IP)
- remote_port: the TCP port of the server (alias: Remote Port)
- size_header: the size of the response headers (alias: Response Header)
- size_download: the size of the downloaded response (alias: Response Length)

NOTE ON FAILED REQUESTS: a request is considered failed when curl returns a non-zero exit code (e.g. DNS failure, connection refused, TLS error, timeout).
A warning with the curl exit code and error message is printed, and the failed request is EXCLUDED from the statistics (otherwise its zero times would corrupt minimum and average). The number of failed requests is reported in the summary. If all the requests fail, the script exits with an error and exit code 1.
HTTP error statuses (e.g. 404, 500) are not considered failures, since the timings of such requests are still valid.

NOTE ON THE MULTIPLE RUNS TABLE: in a single run, and in the Average column, the start time of a row is equal to the start time of the previous row plus its duration (apart from a 0.01 ms rounding in the printed values).
This is NOT true for the Minimum and Maximum columns: each cell is calculated independently across all the runs, so the duration and the start time of a row (and the ones of the previous row) usually come from different runs and therefore do not add up.

.PARAMETER $Uri
Specifies the http / https url to download with a GET request (mandatory, PowerShell prompts for it if missing)

.PARAMETER $LocalIp
Optional. Specifies a local ip address which is automatically used replacing the original DNS resolved ip. If omitted, the normal DNS resolution is used

.PARAMETER $Times
Specifies the number of time the request is performed

.PARAMETER $NoRevoke
Specifies a flag to disables TLS certificate revocation checks

.PARAMETER $ShowAlias
Specifies a flag to display friendly aliases (e.g. "DNS Lookup") instead of the curl metric names. Enabled by default, use -ShowAlias:$false to show the original curl metric names

.INPUTS

None.

.OUTPUTS

Statistics on each phase of the request calculating, minimum, maximum and average

.EXAMPLE

PS> LanSpeed.ps1 -Uri https://www.myserver.com/ -Times 20
PS> LanSpeed.ps1 -Uri https://www.myserver.com/ -LocalIp 192.168.1.50 -Times 20
PS> LanSpeed.ps1 -Uri https://www.myserver.com/ -Times 20 -ShowAlias:$false

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2026 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [Alias('u')] [String] $Uri,
    [ValidateNotNullOrEmpty()] [Alias('l')] [String] $LocalIp,
    [ValidateRange(1, 1000)] [Alias('t')] [Int] $Times = 1,
    [switch] [Alias('r')] $NoRevoke,
    [switch] [Alias('a')] $ShowAlias = $true
)

# Timeline phases returned by curl, in the order curl reaches them (each value is cumulative from request start)
$curlPhaseKeys = @(
    "time_namelookup",
    "time_connect",
    "time_appconnect",
    "time_pretransfer",
    "time_starttransfer",
    "time_total"
)

# Display order: same as above plus the derived "time_download" row (time_total - time_starttransfer)
$phaseKeys = @(
    "time_namelookup",
    "time_connect",
    "time_appconnect",
    "time_pretransfer",
    "time_starttransfer",
    "time_download",
    "time_total"
)

# time_redirect is a duration by itself, not a point on the timeline
$timeKeys = $curlPhaseKeys + @("time_redirect")

# Extra metadata keys
$metaKeys = @(
    "remote_ip",
    "remote_port",
    "size_header",
    "size_download"
)

# Optional friendly names for the metrics
$metricAliases = @{
    "time_namelookup"    = "DNS Lookup"
    "time_connect"       = "TCP Connect"
    "time_appconnect"    = "TLS Tunnel"
    "time_pretransfer"   = "Sending Request"
    "time_starttransfer" = "Server Processing"
    "time_download"      = "Receiving Response"
    "time_total"         = "Elapsed Time"
    "time_redirect"      = "Redirect Overhead"
    "remote_ip"          = "Remote IP"
    "remote_port"        = "Remote Port"
    "size_header"        = "Response Header"
    "size_download"      = "Response Length"
}

# Combine keys for curl format configuration (the derived time_download is not requested from curl)
$allKeys = $timeKeys + $metaKeys
$customFormat = ($allKeys | ForEach-Object { "[${_}:%{${_}}]" }) -join ""

# Returns the alias of a metric when -ShowAlias is enabled and an alias exists, otherwise the metric name
function Get-MetricName($Key) {
    if ($ShowAlias -and $metricAliases.ContainsKey($Key)) { return $metricAliases[$Key] }
    return $Key
}

# Formats "duration ms (start ms)"; returns "n/a" when the phase did not happen
function Format-Phase($Duration, $Start) {
    if ($null -eq $Duration) { return "n/a" }
    return "{0:F2} ms ({1:F2} ms)" -f ($Duration * 1000), ($Start * 1000)
}

# Min / Average / Max of a list of values (nulls are ignored)
function Get-Stats($Values) {
    $v = @($Values | Where-Object { $null -ne $_ })
    if ($v.Count -eq 0) { return $null }
    return $v | Measure-Object -Minimum -Maximum -Average
}

# Storage for results across all iterations (only successful requests are stored)
$allRuns = @()
$failedRuns = 0

Write-Host "Executing $Times iteration(s)..." -ForegroundColor Cyan

for ($i = 1; $i -le $Times; $i++) {
    # Prepare curl arguments array (-s silences the progress meter, -S still shows errors)
    $curlArgs = @(
        "-w", $customFormat,
        "-s",
        "-S",
        "-o", "NUL"
    )
    # Override the DNS resolved ip only when a local ip was specified
    if ($LocalIp) { $curlArgs += @("--resolve", "*:443:$LocalIp", "--resolve", "*:80:$LocalIp") }
    if ($NoRevoke) { $curlArgs += "--ssl-no-revoke" }
    $curlArgs += $Uri

    # Execute curl natively, keeping stdout (the -w metrics) and stderr (error messages) separated
    $raw      = & curl.exe @curlArgs 2>&1
    $exitCode = $LASTEXITCODE
    $output   = ($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join ""
    $errText  = ($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString().Trim() }) -join " "

    # A failed request (curl exit code <> 0) has meaningless zero times: warn and exclude it from the statistics
    if ($exitCode -ne 0) {
        $failedRuns++
        Write-Warning "Iteration $i failed (curl exit code $exitCode): $errText"
        continue
    }

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

    # Compute the duration of each phase = its time minus the time of the previous phase
    # The start of a phase is the end of the previous one (the first phase starts at 0)
    $prev = 0.0
    foreach ($key in $curlPhaseKeys) {
        $v = $runMetrics[$key]
        if ($key -eq "time_appconnect" -and $v -eq 0) {
            # No TLS handshake (plain http): the phase does not exist
            $runMetrics["start_$key"] = $null
            $runMetrics["dur_$key"]   = $null
        } else {
            $runMetrics["start_$key"] = $prev
            $runMetrics["dur_$key"]   = $v - $prev
            $prev = $v
        }
    }

    # Derived phase: body download = time_total - time_starttransfer
    # (it starts when the first byte arrived, i.e. at time_starttransfer)
    $runMetrics["start_time_download"] = $runMetrics["time_starttransfer"]
    $runMetrics["dur_time_download"]   = $runMetrics["time_total"] - $runMetrics["time_starttransfer"]

    $allRuns += [PSCustomObject]$runMetrics
}

# Nothing to report if every request failed
if ($allRuns.Count -eq 0) {
    Write-Error "All $Times request(s) failed, no statistics available."
    exit 1
}

# If only 1 run was requested, print a clean list view
if ($Times -eq 1) {
    $run = $allRuns[0]
    $singleRunTable = [ordered]@{}
    foreach ($key in $phaseKeys) {
        if ($key -eq "time_total") {
            # Raw total elapsed time, no difference with the previous phase
            $singleRunTable[(Get-MetricName $key)] = "{0:F2} ms" -f ($run.$key * 1000)
        } else {
            $singleRunTable[(Get-MetricName $key)] = Format-Phase $run."dur_$key" $run."start_$key"
        }
    }
    $singleRunTable[(Get-MetricName "time_redirect")] = "{0:F2} ms" -f ($run.time_redirect * 1000)
    foreach ($key in $metaKeys) {
        if ($key -like "size*") {
            $singleRunTable[(Get-MetricName $key)] = "{0:N0} bytes" -f $run.$key
        } else {
            $singleRunTable[(Get-MetricName $key)] = $run.$key
        }
    }
    Write-Host "`nFormat: duration (start time since request start); total is the raw value" -ForegroundColor DarkGray
    [PSCustomObject]$singleRunTable | Format-List
}
else {
    $rows = @()

    # Timeline phases: statistics on the per-run duration, with the statistics of the start time in parenthesis
    # NOTE: only the Average column is consistent (start of a row = start of the previous row + its duration).
    # Minimum and Maximum are calculated independently for each cell, so their duration and start values come from
    # different runs and do not add up across rows. This is expected, not a rounding error.
    foreach ($key in $phaseKeys) {
        if ($key -eq "time_total") {
            # Raw total elapsed time, no difference with the previous phase
            $totStats = Get-Stats ($allRuns | ForEach-Object { $_.$key })
            $min = "{0:F2} ms" -f ($totStats.Minimum * 1000)
            $avg = "{0:F2} ms" -f ($totStats.Average * 1000)
            $max = "{0:F2} ms" -f ($totStats.Maximum * 1000)
        } else {
            $durStats   = Get-Stats ($allRuns | ForEach-Object { $_."dur_$key" })
            $startStats = Get-Stats ($allRuns | ForEach-Object { if ($null -ne $_."dur_$key") { $_."start_$key" } })

            if ($null -eq $durStats) {
                $min = $avg = $max = "n/a"
            } else {
                $min = Format-Phase $durStats.Minimum   $startStats.Minimum
                $avg = Format-Phase $durStats.Average   $startStats.Average
                $max = Format-Phase $durStats.Maximum   $startStats.Maximum
            }
        }

        $rows += [PSCustomObject]@{ Metric = (Get-MetricName $key); Minimum = $min; Average = $avg; Maximum = $max }
    }

    # time_redirect is already a duration
    $redirStats = Get-Stats ($allRuns | ForEach-Object { $_.time_redirect })
    $rows += [PSCustomObject]@{
        Metric  = (Get-MetricName "time_redirect")
        Minimum = "{0:F2} ms" -f ($redirStats.Minimum * 1000)
        Average = "{0:F2} ms" -f ($redirStats.Average * 1000)
        Maximum = "{0:F2} ms" -f ($redirStats.Maximum * 1000)
    }

    # Add metadata entries as rows (static values across runs)
    $lastRun = $allRuns[-1]
    foreach ($key in $metaKeys) {
        $valStr = if ($key -like "size*") { "{0:N0} bytes" -f $lastRun.$key } else { $lastRun.$key }
        $rows += [PSCustomObject]@{ Metric = (Get-MetricName $key); Minimum = $valStr; Average = $valStr; Maximum = $valStr }
    }

    Write-Host "`n=== BENCHMARK SUMMARY OVER $($allRuns.Count) SUCCESSFUL ITERATION(S) ===" -ForegroundColor Green
    if ($failedRuns -gt 0) {
        Write-Host "$failedRuns of $Times request(s) failed and were excluded from the statistics" -ForegroundColor Yellow
    }
    Write-Host "Format: duration (start time since request start); total is the raw value" -ForegroundColor DarkGray
    $rows | Format-Table -Property Metric, Minimum, Average, Maximum -AutoSize
}