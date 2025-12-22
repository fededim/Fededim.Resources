# Run as administrator
# powershell.exe -ExecutionPolicy bypass -Command "(Get-WmiObject -Namespace "root\CIMV2\Security\MicrosoftTpm" -Class Win32_TPM).SetPhysicalPresenceRequest(97)"
(Get-WmiObject -Namespace "root\CIMV2\Security\MicrosoftTpm" -Class Win32_TPM).SetPhysicalPresenceRequest(97)
