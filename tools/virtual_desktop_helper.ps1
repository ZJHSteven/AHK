param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("is-current", "move-to-current")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [long]$TargetHwnd,

    [long]$AnchorHwnd = 0
)

$ErrorActionPreference = "Stop"

Add-Type @"
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IVirtualDesktopManager
{
    [PreserveSig]
    int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, out bool onCurrentDesktop);

    [PreserveSig]
    int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);

    [PreserveSig]
    int MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
}

public static class VirtualDesktopBridge
{
    public static IVirtualDesktopManager CreateManager()
    {
        Type clsid = Type.GetTypeFromCLSID(new Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a"));
        object instance = Activator.CreateInstance(clsid);
        return (IVirtualDesktopManager)instance;
    }
}
"@

function Assert-HResult {
    param(
        [int]$HResult,
        [string]$Operation
    )

    if ($HResult -ne 0) {
        $message = "{0} failed, HRESULT=0x{1:X8}" -f $Operation, ($HResult -band 0xFFFFFFFF)
        throw $message
    }
}

$manager = [VirtualDesktopBridge]::CreateManager()
$targetPtr = [IntPtr]::new($TargetHwnd)

switch ($Mode) {
    "is-current" {
        $onCurrent = $false
        $hr = $manager.IsWindowOnCurrentVirtualDesktop($targetPtr, [ref]$onCurrent)
        Assert-HResult $hr "IsWindowOnCurrentVirtualDesktop"
        if ($onCurrent) {
            Write-Output "1"
        } else {
            Write-Output "0"
        }
        exit 0
    }

    "move-to-current" {
        if ($AnchorHwnd -le 0) {
            throw "move-to-current requires a valid AnchorHwnd."
        }

        $anchorPtr = [IntPtr]::new($AnchorHwnd)
        $desktopId = [Guid]::Empty
        $hr = $manager.GetWindowDesktopId($anchorPtr, [ref]$desktopId)
        Assert-HResult $hr "GetWindowDesktopId"

        $hr = $manager.MoveWindowToDesktop($targetPtr, [ref]$desktopId)
        Assert-HResult $hr "MoveWindowToDesktop"

        Write-Output "1"
        exit 0
    }
}
