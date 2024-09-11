<#
.SYNOPSIS

Takes ownership and full control of all local private queues

.DESCRIPTION

You must specify the user to which assign the new ownership in $User variable

.PARAMETER User
Specifies the user which will take the ownership of all queues, format domain\username

.INPUTS

None.

.OUTPUTS

None

.EXAMPLE

PS> TakeOwnershipAndFullControlOfMessageQueues -u "DOMAIN\USER"

.LINK

https://github.com/fededim/Fededim.Resources/tree/master/PowershellResources

.NOTES

© 2023 Federico Di Marco <fededim@gmail.com>

Implementation of this script is partially borrowed from https://github.com/gavacho/System.Messaging.MessageQueue.SetOwner/blob/master/System.Messaging.MessageQueue.SetOwner.cs
#>
[CmdletBinding()]
param (
	[Parameter(Mandatory=$true)]  [Alias('u')] [String] $User
	)

	Import-Module -Name MSMQ

	function GrantFullAccessToMessageQueue([Microsoft.Msmq.PowerShell.Commands.MessageQueue]$queue, [string]$principal)
	{
		Write-Host "Granting permission to $($queue.QueueName)"

		[System.Messaging.MessageQueueExtensions]::SetOwner(".\"+$queue.QueueName,$principal)
		Set-MsmqQueueAcl -InputObject $queue -UserName $principal -Allow TakeQueueOwnership
		Set-MsmqQueueAcl -InputObject $queue -UserName $principal -Allow FullControl
	}


	Add-Type -AssemblyName "System.Messaging"

	Add-Type -ReferencedAssemblies System.Messaging -TypeDefinition '
	using System.ComponentModel;
	using System.Runtime.InteropServices;
	using System.Security.Principal;

	namespace System.Messaging
	{
		public static partial class MessageQueueExtensions
		{
			public static class Win32
			{
				public const int SECURITY_DESCRIPTOR_REVISION = 1;
				public const int OWNER_SECURITY_INFORMATION = 1;

				[StructLayout(LayoutKind.Sequential)]
				public class SECURITY_DESCRIPTOR
				{
					public byte revision;
					public byte size;
					public short control;
					public IntPtr owner;
					public IntPtr group;
					public IntPtr sacl;
					public IntPtr dacl;
				}


				[StructLayoutAttribute(LayoutKind.Sequential)]
				public struct TOKEN_PRIVILEGES
				{
					public uint PrivilegeCount;
					[MarshalAsAttribute(UnmanagedType.ByValArray, SizeConst = 1, ArraySubType = UnmanagedType.Struct)]
					public LUID_AND_ATTRIBUTES[] Privileges;
				}
	

				[StructLayoutAttribute(LayoutKind.Sequential)]
				public struct LUID
				{
					public uint LowPart;
					public int HighPart;
				}

		
				[StructLayoutAttribute(LayoutKind.Sequential)]
				public struct LUID_AND_ATTRIBUTES
				{
					public LUID Luid;
					public uint Attributes;
				}

				[DllImport("advapi32.dll", SetLastError = true)]
				public static extern UInt32  InitializeSecurityDescriptor(SECURITY_DESCRIPTOR SD, int revision);

				[DllImport("advapi32.dll", SetLastError = true)]
				public static extern UInt32  SetSecurityDescriptorOwner(SECURITY_DESCRIPTOR pSecurityDescriptor, byte[] pOwner, bool bOwnerDefaulted);

				[DllImport("mqrt.dll", SetLastError = true, CharSet = CharSet.Unicode)]
				public static extern UInt32  MQSetQueueSecurity(string lpwcsFormatName, int SecurityInformation, SECURITY_DESCRIPTOR pSecurityDescriptor);
			
				[DllImport("kernel32.dll")]
				public static extern UInt32 GetLastError();
			
				[DllImportAttribute("advapi32.dll", EntryPoint = "OpenProcessToken")]
				[return: MarshalAsAttribute(UnmanagedType.Bool)]
				public static extern bool OpenProcessToken([InAttribute] IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

				[DllImportAttribute("kernel32.dll", EntryPoint = "CloseHandle")]
				[return: MarshalAsAttribute(UnmanagedType.Bool)]
				public static extern bool CloseHandle([InAttribute] IntPtr hObject);
			
				[DllImportAttribute("advapi32.dll", EntryPoint = "AdjustTokenPrivileges")]
				[return: MarshalAsAttribute(UnmanagedType.Bool)]
				public static extern bool AdjustTokenPrivileges([InAttribute()] IntPtr TokenHandle,[MarshalAsAttribute(UnmanagedType.Bool)] bool DisableAllPrivileges,[InAttribute()] ref TOKEN_PRIVILEGES NewState,uint BufferLength,IntPtr PreviousState,IntPtr ReturnLength);
			
				[DllImportAttribute("kernel32.dll", EntryPoint = "GetCurrentProcess")]
				public static extern IntPtr GetCurrentProcess();

				[DllImportAttribute("advapi32.dll", EntryPoint = "LookupPrivilegeValueA")]
				[return: MarshalAsAttribute(UnmanagedType.Bool)]
				public static extern bool LookupPrivilegeValueA([InAttribute] [MarshalAsAttribute(UnmanagedType.LPStr)] string lpSystemName,[InAttribute] [MarshalAsAttribute(UnmanagedType.LPStr)] string lpName,[OutAttribute] out LUID lpLuid);

				public const UInt32 TOKEN_ADJUST_PRIVILEGES = 0x0020;
				public const int NO_INHERITANCE = 0x0;
				public const int SECURITY_BUILTIN_DOMAIN_RID = 0x00000020;
				public const int DOMAIN_ALIAS_RID_ADMINS = 0x00000220;
				public const int TOKEN_QUERY = 8;
				public const int SE_PRIVILEGE_ENABLED = 2;
				public const string SE_TAKE_OWNERSHIP_NAME = "SeTakeOwnershipPrivilege";

				public static void SetPrivilege(string privilege) {
					// enable privilege for current user
					LUID luid;
					IntPtr token = IntPtr.Zero;
					TOKEN_PRIVILEGES tokenPrivileges = new TOKEN_PRIVILEGES();
					Win32.OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY, out token);
					LookupPrivilegeValueA(null, privilege, out luid);
					tokenPrivileges.PrivilegeCount = 1;
					tokenPrivileges.Privileges = new LUID_AND_ATTRIBUTES[1];
					tokenPrivileges.Privileges[0].Luid = luid;
					tokenPrivileges.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

					AdjustTokenPrivileges(token, false, ref tokenPrivileges, 0,IntPtr.Zero, IntPtr.Zero);
					CloseHandle(token);
				}
			}
		

			public static void SetOwner(this String queueName, string name, bool ownerDefaulted = false)
			{
				SetOwner(queueName, new NTAccount(name), ownerDefaulted);
			}

			public static void SetOwner(this String queueName, IdentityReference identity, bool ownerDefaulted = false)
			{
				var securityIdentifier = (SecurityIdentifier)identity.Translate(typeof(SecurityIdentifier));
				SetOwner(queueName, securityIdentifier, ownerDefaulted);
			}

			public static void SetOwner(this String queueName, SecurityIdentifier sid, bool ownerDefaulted = false)
			{
				var buffer = new byte[sid.BinaryLength];
				sid.GetBinaryForm(buffer, 0);
				SetOwner(queueName, buffer, ownerDefaulted);
			}

			public static void SetOwner(this String queueName, byte[] sid, bool ownerDefaulted = false)
			{
				// obtain 
				Win32.SetPrivilege(Win32.SE_TAKE_OWNERSHIP_NAME);

				// set queue owner
			
				var queue = new MessageQueue(queueName);
			
				UInt32 result;

				var securityDescriptor = new Win32.SECURITY_DESCRIPTOR();
				if ((result=Win32.InitializeSecurityDescriptor(securityDescriptor, Win32.SECURITY_DESCRIPTOR_REVISION))==0)
					throw new Exception(String.Format("Unable to initialize security descriptor: {0:X}",result));
		
				if ((result=Win32.SetSecurityDescriptorOwner(securityDescriptor, sid, ownerDefaulted))==0)
					throw new Exception(String.Format("Unable to set security descriptor: {0:X}",result));

				if ((result=Win32.MQSetQueueSecurity(queue.FormatName, Win32.OWNER_SECURITY_INFORMATION, securityDescriptor))!=0)
					throw new Exception(String.Format("Unable to set security on queue: {0:X}",result));
			}
		}
	}'

	$allqueues = Get-MsmqQueue -QueueType Private

	foreach ($queue in $allqueues) {
		GrantFullAccessToMessageQueue $queue $User
	}