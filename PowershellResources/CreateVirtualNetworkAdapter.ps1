<#
.SYNOPSIS

Utility to create a Hyper-V virtual network adapter with a custom VLAN value for restricting local LAN access to virtual machines.

.DESCRIPTION

Utility to create a Hyper-V virtual network adapter with a custom VLAN value for restricting local LAN access to virtual machines.

.PARAMETER VLANTag
Specifies the VLAN ID to assign to the new virtual network adapter

.INPUTS

None.

.OUTPUTS

None

.EXAMPLE

PS> Create-VirtualNetworkAdapter -t 15

Creates a virtual network adapter with VLAN ID 15

PS> Create-VirtualNetworkAdapter -t 20

Creates a virtual network adapter with VLAN ID 20

To list all VMNetworkAdapters: Get-VMNetworkAdapter -ManagementOS
To remove a VMNetworkAdapter: Remove-VMNetworkAdapter -ManagementOS -Name "<name>"
To remove all VMNetworkAdapter created: Get-VMNetworkAdapter -ManagementOS | Where-Object { $($_.Name).StartsWith("VLAN") } | Remove-VMNetworkAdapter
To remove a VMSwitch: Remove-VMSwitch -name "<name>"

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources
https://github.com/fededim/Fededim.Resources/blob/master/LICENSE.txt

.NOTES

© 2026 Federico Di Marco <fededim@gmail.com> released under MIT LICENSE 
#>
[CmdletBinding()]
param (
    [ValidateNotNullOrEmpty()] [Alias('v')] [int] $VLANId = 10
)

$ErrorActionPreference = 'Stop'

# checks hyperV is installed
# $hyperVStatus = (Get-WindowsOptionalFeature -Online -FeatureName HyperVPlatform)
# $hyperVPowershellStatus = (Get-WindowsOptionalFeature -Online -FeatureName HyperVPowerShell)

# if (($hyperVStatus.State -ne "Enabled") -or ($hyperVPowershellStatus.State -ne "Enabled")) {
	# Write-Host "`nMissing features detected. Installing full Hyper-V stack with management tools..." -ForegroundColor Cyan
    
    # # Using -All ensures all sub-components, including the modules, are pulled down
    # Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All	
# }

if ($VLANId -lt 2 -or $VLANId -gt 4094) {
    throw [System.ArgumentOutOfRangeException]"[ERROR] VLANTag parameter is out of bounds. It must be strictly between 2 and 4094."
}

$adapters = (Get-NetAdapter)
Write-Host "=== Select a Network Interface ===" -ForegroundColor Cyan
$adapters | Format-Table -AutoSize

do {
    $selectedIfIndex = Read-Host "Enter the Index number of the interface you want to choose"
    $chosenAdapter = $adapters | Where-Object { $_.IfIndex -eq $selectedIfIndex }
    
    if (-not $chosenAdapter) {
        Write-Host "Invalid selection. Please try again." -ForegroundColor Red
    }
} while (-not $chosenAdapter)

Write-Host "`n`nSelected Network Interface:" -ForegroundColor Cyan
$chosenAdapter | Format-Table -AutoSize

$vmSwitchName = "VLANSwitch"
$vmNetworkAdapaterName = "VLAN$($VLANId)Net_$($chosenAdapter.Name)"

$existingSwitch = (Get-VMSwitch | Where-Object { $_.NetAdapterInterfaceDescription -eq $($chosenAdapter.InterfaceDescription) })
if (-not $existingSwitch) {
	New-VMSwitch -Name "$vmSwitchName" -NetAdapterName "$($chosenAdapter.Name)" -AllowManagementOS $true
	Write-Host "`nCreated succesfully HyperV Switch $vmSwitchName" -ForegroundColor Cyan
}
else {
	$vmSwitchName = $($existingSwitch.Name)
	Write-Host "`nUsing existing HyperV Switch $vmSwitchName" -ForegroundColor Cyan
}

if (-not (Get-VMNetworkAdapter -ManagementOS -Name $vmNetworkAdapaterName -ErrorAction SilentlyContinue)) {
	Add-VMNetworkAdapter -ManagementOS -Name "$vmNetworkAdapaterName" -SwitchName "$vmSwitchName"
	Write-Host "`nCreated HyperV Virtual Network Adapter $vmNetworkAdapaterName" -ForegroundColor Cyan
}

Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName "$vmNetworkAdapaterName" -Access -VlanId $VLANId
Write-Host "`nAssigned VLAN $VLANId to Virtual Network Adapter $vmNetworkAdapaterName" -ForegroundColor Cyan

Write-Host "`n`nDumping configuration for safety" -ForegroundColor Cyan
Get-VMNetworkAdapter -ManagementOS | Format-Table -AutoSize
Get-VMNetworkAdapterVlan -ManagementOS | Format-Table -AutoSize

