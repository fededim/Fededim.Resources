<#
.SYNOPSIS

Utility to enforce the use of DoH encrypted Comodo's DNS server for increased privacy

.DESCRIPTION

Utility to enforce the use of DoH encrypted Comodo's DNS server for increased privacy on all connected network interfaces

.PARAMETER IfIndexes
Specifies the IfIndex values of the network interfaces to configure. If omitted (null), the list of network interfaces is shown and the user is asked to enter one or more IfIndex values separated by space. If an empty array is passed, all interfaces are skipped.

.PARAMETER All
If set, encrypted DNS is applied to all network interfaces, regardless of the value of IfIndexes (no prompt is shown).

.PARAMETER DnsServers
Specifies the hashtable consisting of the dns server ip address with the associated Dns-Over-Https (DoH) template.

.INPUTS

None.

.OUTPUTS

Log information.

.EXAMPLE

PS> EnforceEncryptedDns.ps1

Shows the list of network interfaces and asks which IfIndex values (separated by space) to configure

PS> EnforceEncryptedDns.ps1 -All

Applies encrypted DNS to all possible interfaces without asking anything

PS> EnforceEncryptedDns.ps1 -i @(4,12,25)

Applies encrypted DNS to interfaces with IfIndex equal to 4, 12, 25

PS> EnforceEncryptedDns.ps1 -i @()

Skips all interfaces, but it show all their names and IfIndex value

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt
https://learn.microsoft.com/en-GB/windows-server/networking/dns/doh-client-support

.NOTES

© 2025 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param(
	# configured Comodo's DNS by default
	[AllowNull()] [Alias('i')] [String[]] $IfIndexes,
	[Alias('a')] [Switch] $All,
	[ValidateNotNullOrEmpty()] [Alias('d')] [Hashtable] $DnsServers = @{
		"1.1.1.1" = 'https://security.cloudflare-dns.com/dns-query'
		"1.0.0.1" = 'https://security.cloudflare-dns.com/dns-query'
		"2606:4700:4700::1111" = 'https://security.cloudflare-dns.com/dns-query'
		"2606:4700:4700::1001" = 'https://security.cloudflare-dns.com/dns-query'
	}
)

# Interfaces list (same set which is processed by the update loop below)
$adapters = @(Get-NetAdapter -IncludeHidden | Sort-Object -Property ifIndex)

# If neither -All nor -IfIndexes has been specified, show interfaces and ask the user which ones to configure
if (-not $All -and $null -eq $IfIndexes) {
	$ipByIndex = @{}
	foreach ($ip in (Get-NetIPAddress -ErrorAction SilentlyContinue)) {
		$idx = [int]$ip.InterfaceIndex
		if (-not $ipByIndex.ContainsKey($idx)) { $ipByIndex[$idx] = @() }
		$ipByIndex[$idx] += $ip.IPAddress
	}

	$adapters | ForEach-Object {
		[PSCustomObject]@{
			Index       = $_.ifIndex
			Name        = $_.InterfaceAlias
			Description = $_.InterfaceDescription
			Status      = $_.Status
			IPAddress   = ($ipByIndex[[int]$_.ifIndex] -join ', ')
		}
	} | Sort-Object -Property Name | Format-Table -AutoSize -Wrap | Out-Host

	$answer = Read-Host "Enter one or more interface indexes (Index column) separated by space"
	$selected = @()
	foreach ($token in ($answer -split '[\s,]+' | Where-Object { $_ })) {
		if ($token -match '^\d+$' -and [int]$token -in $adapters.ifIndex) {
			$selected += [int]$token
		}
		else {
			Write-Host "Ignoring invalid interface index '$token'" -Foreground Yellow
		}
	}

	if ($selected.Count -eq 0) {
		Write-Host "No valid interface index selected, nothing to do." -Foreground Red
		return
	}

	$IfIndexes = $selected
}

#Add dns server with template to well known list
foreach ($keyValuePair in $DnsServers.GetEnumerator()) {
	if ((Get-DnsClientDohServerAddress -ServerAddress $($keyValuePair.Name) -ErrorAction SilentlyContinue) -eq $null) {
		Add-DnsClientDohServerAddress -ServerAddress $($keyValuePair.Name) -DohTemplate $($keyValuePair.Value) -AllowFallbackToUdp $False -AutoUpgrade $True
	}
	else {
		Set-DnsClientDohServerAddress -ServerAddress $($keyValuePair.Name) -DohTemplate $($keyValuePair.Value) -AllowFallbackToUdp $False -AutoUpgrade $True
	}

    Write-Host "Configured DNS server $($keyValuePair.Name) with template $($keyValuePair.Value) to well known list" -Foreground Green
}

#Set DNSClient group policy to require dns encryption

# Check if "DNSClient" exists in "HKLM\Software\Policies\Microsoft\Windows NT\" registry key
if (!(Test-Path -Path "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient")) {
    New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows NT\" -Name DNSClient | Out-Null
}

Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient" -Name "DoHPolicy" -Value 3 -Type DWord -Force
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient" -Name "DohPolicySetting" -Value 0 -Type DWord -Force
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient" -Name "DotPolicySetting" -Value 0 -Type DWord -Force

Write-Host "`nConfigured DNSClient group policy to require DNS encryption`n" -Foreground Green

# Update
foreach ($adapter in $adapters)  {
	if (-not $All -and $adapter.IfIndex -notin $IfIndexes) {
		continue
	}	

    Write-Host "Configuring encrypted dns on interface $($adapter.InterfaceAlias) (Index $($adapter.ifIndex) InstanceId $($adapter.InstanceId))"
	Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ([String[]]$DnsServers.Keys) -ErrorAction SilentlyContinue

	if ($? -eq $False) {
		Write-Host "Troublesome interface, skipping...`n" -Foreground Red
		continue
	}
	
	if (!(Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.InstanceId)")) {
		New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters" -Name $($adapter.InstanceId) | Out-Null
	}

	if (!(Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.InstanceId)\DohInterfaceSettings")) {
		New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.InstanceId)" -Name "DohInterfaceSettings" | Out-Null
	}

	if (!(Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.InstanceId)\DohInterfaceSettings\Doh")) {
		New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.InstanceId)\DohInterfaceSettings" -Name "Doh" | Out-Null
	}

	if (!(Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.InstanceId)\DohInterfaceSettings\Doh6")) {
		New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.InstanceId)\DohInterfaceSettings" -Name "Doh6" | Out-Null
	}

	foreach ($keyValuePair in $DnsServers.GetEnumerator()) {
		$subDohKey = If ($($keyValuePair.Name).Contains(':')) {"Doh6"} Else {"Doh"}
		$keyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.InstanceId)\DohInterfaceSettings\$subDohKey"

		if (!(Test-Path -Path "$keyPath\$($keyValuePair.Name)")) {
			New-Item -Path $keyPath -Name $($keyValuePair.Name) | Out-Null
		}

		Set-ItemProperty -Path "$keyPath\$($keyValuePair.Name)" -Name "DohFlags" -Value 1 -Type QWord -Force
		Set-ItemProperty -Path "$keyPath\$($keyValuePair.Name)" -Name "DohTemplate" -Value $($keyValuePair.Value) -Type String -Force
	}

	Restart-NetAdapter -Name $adapter.InterfaceAlias

	Write-Host "All done`n" -Foreground Green
}

Clear-DnsClientCache