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
    int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, out bool onCurrentDesktop);
    int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);
    int MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
}

public static class VirtualDesktopNative
{
    [DllImport("ole32.dll", ExactSpelling = true)]
    private static extern int CoCreateInstance(
        [In] ref Guid rclsid,
        IntPtr pUnkOuter,
        uint dwClsContext,
        [In] ref Guid riid,
        out IntPtr ppv);

    private static IVirtualDesktopManager CreateManager()
    {
        Guid clsidVirtualDesktopManager = new Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a");
        Guid iidVirtualDesktopManager = new Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b");
        IntPtr ppv;
        int hr = CoCreateInstance(ref clsidVirtualDesktopManager, IntPtr.Zero, 1u, ref iidVirtualDesktopManager, out ppv);
        if (hr != 0)
        {
            Marshal.ThrowExceptionForHR(hr);
        }

        try
        {
            return (IVirtualDesktopManager)Marshal.GetObjectForIUnknown(ppv);
        }
        finally
        {
            Marshal.Release(ppv);
        }
    }

    public static bool IsOnCurrentDesktop(long hwnd)
    {
        IVirtualDesktopManager manager = CreateManager();
        bool onCurrent = false;
        int hr = manager.IsWindowOnCurrentVirtualDesktop(new IntPtr(hwnd), out onCurrent);
        if (hr != 0)
        {
            Marshal.ThrowExceptionForHR(hr);
        }
        return onCurrent;
    }

    public static void MoveWindowToCurrentDesktop(long targetHwnd, long anchorHwnd)
    {
        IVirtualDesktopManager manager = CreateManager();
        Guid desktopId;
        int hr = manager.GetWindowDesktopId(new IntPtr(anchorHwnd), out desktopId);
        if (hr != 0)
        {
            Marshal.ThrowExceptionForHR(hr);
        }

        hr = manager.MoveWindowToDesktop(new IntPtr(targetHwnd), ref desktopId);
        if (hr != 0)
        {
            Marshal.ThrowExceptionForHR(hr);
        }
    }
}
"@

switch ($Mode) {
    "is-current" {
        if ([VirtualDesktopNative]::IsOnCurrentDesktop($TargetHwnd)) {
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

        [VirtualDesktopNative]::MoveWindowToCurrentDesktop($TargetHwnd, $AnchorHwnd)
        Write-Output "1"
        exit 0
    }
}
