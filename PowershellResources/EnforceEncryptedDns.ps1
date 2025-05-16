<#
.SYNOPSIS

Utility to enforce the use of DoH encrypted Comodo's DNS server for increased privacy

.DESCRIPTION

Utility to enforce the use of DoH encrypted Comodo's DNS server for increased privacy on all connected network interfaces

.PARAMETER DnsServers
Specifies the hashtable consisting of the dns server ip address with the associated Dns-Over-Https (DoH) template.

.INPUTS

None.

.OUTPUTS

Log information.

.EXAMPLE

PS> EnforceEncryptedDns.ps1

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
	[ValidateNotNullOrEmpty()] [Alias('d')] [Hashtable] $DnsServers = @{
		"1.1.1.1" = 'https://security.cloudflare-dns.com/dns-query'
		"1.0.0.1" = 'https://security.cloudflare-dns.com/dns-query'
		"2606:4700:4700::1111" = 'https://security.cloudflare-dns.com/dns-query'
		"2606:4700:4700::1001" = 'https://security.cloudflare-dns.com/dns-query'
	}
)

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
foreach ($adapter in (Get-NetAdapter -IncludeHidden | Where-Object Virtual -eq $False))  {
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
