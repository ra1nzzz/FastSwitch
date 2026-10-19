#requires -Version 5.1
<#
  MonitorInput.ps1 - Zero-dependency DDC/CI control for the AOC U27U2DS.

  Uses only the built-in Windows APIs (user32.dll + dxva2.dll) through an
  inline C# interop class. No ControlMyMonitor, PowerToys, Python or any
  other third-party component is required.

  Tested on: Windows 11, ASUS TUF A15 (HDMI2) -> AOC U27U2DS (2026-10-19).

  Actions:
    list                         List physical monitors + descriptions
    get                          Read current input source (VCP 0x60)
    caps                         Dump the monitor DDC capabilities string
    dump                         Read a set of common VCP codes
    usbc                         Set input = USB-C (27)
    dp | dp1                     Set input = DisplayPort 1 (15)
    dp2                          Set input = DisplayPort 2 (16)
    hdmi1                        Set input = HDMI 1 (17)
    hdmi2                        Set input = HDMI 2 (18)
    set <value>                  Set VCP 0x60 to a decimal value
    getcode -Code <hex>          Read any VCP code (e.g. -Code CC)
    setcode -Code <hex> -Value <dec>
                                 Set any VCP code (e.g. -Code CC -Value 5)

  Examples:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorInput.ps1 get
    powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorInput.ps1 usbc
    powershell -NoProfile -ExecutionPolicy Bypass -File .\MonitorInput.ps1 getcode -Code CC
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'get', 'caps', 'dump', 'usbc', 'dp', 'dp1', 'dp2',
                 'hdmi1', 'hdmi2', 'set', 'getcode', 'setcode')]
    [string]$Action = 'get',

    [Parameter(Position = 1)]
    [int]$Value,

    [string]$Code
)

if ($Action -in @('set', 'setcode') -and -not $PSBoundParameters.ContainsKey('Value')) {
    Write-Error "Action '$Action' requires -Value (decimal)."
    exit 1
}
if ($Action -in @('set', 'setcode') -and $Value -lt 0) {
    Write-Error "-Value must be zero or greater."
    exit 1
}

# ---------------------------------------------------------------------------
# Inline C# interop with the Windows low-level monitor APIs (dxva2 / user32).
# ---------------------------------------------------------------------------
$source = @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class DDC
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor,
                                         ref RECT lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip,
                                                  MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("dxva2.dll")]
    public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(
        IntPtr hMonitor, out uint pdwNumberOfPhysicalMonitors);

    [DllImport("dxva2.dll")]
    public static extern bool GetPhysicalMonitorsFromHMONITOR(
        IntPtr hMonitor, uint dwPhysicalMonitorArraySize,
        [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll")]
    public static extern bool DestroyPhysicalMonitors(
        uint dwPhysicalMonitorArraySize, PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll")]
    public static extern bool SetVCPFeature(IntPtr hMonitor, byte bVCPCode,
                                            uint dwNewValue);

    [DllImport("dxva2.dll")]
    public static extern bool GetVCPFeatureAndVCPFeatureReply(
        IntPtr hMonitor, byte bVCPCode, IntPtr pvct,
        out uint pdwCurrentValue, out uint pdwMaximumValue);

    [DllImport("dxva2.dll")]
    public static extern bool GetCapabilitiesStringLength(
        IntPtr hMonitor, out uint pdwCapabilitiesStringLengthInCharacters);

    [DllImport("dxva2.dll")]
    public static extern bool CapabilitiesRequestAndCapabilitiesReply(
        IntPtr hMonitor, StringBuilder pszASCIICapabilitiesString,
        uint dwCapabilitiesStringLengthInCharacters);
}
"@

Add-Type -TypeDefinition $source -Language CSharp

# Input Select (VCP 0x60) values for the U27U2DS.
$InputTargets = @{
    'usbc'  = 27
    'dp'    = 15
    'dp1'   = 15
    'dp2'   = 16
    'hdmi1' = 17
    'hdmi2' = 18
}

# Common VCP codes for "dump" (from the U27U2DS capabilities set).
$DumpCodes = @(
    @{ Code = [byte]0x10; Name = 'Luminance (brightness)' },
    @{ Code = [byte]0x12; Name = 'Contrast' },
    @{ Code = [byte]0x14; Name = 'Color temperature select' },
    @{ Code = [byte]0x60; Name = 'Input Select' },
    @{ Code = [byte]0x62; Name = 'Audio speaker volume' },
    @{ Code = [byte]0xCC; Name = 'OSD language' },
    @{ Code = [byte]0xD6; Name = 'Power mode' },
    @{ Code = [byte]0xDC; Name = 'Display power mode' }
)

function Resolve-Code([string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Output "ERROR: -Code is required (hex, e.g. -Code CC)."
        exit 1
    }
    try {
        return [byte]([Convert]::ToInt32($raw, 16))
    } catch {
        Write-Output "ERROR: -Code '$raw' is not a valid hexadecimal value."
        exit 1
    }
}

function Invoke-Action($handle, [int]$index) {
    Write-Output "[Monitor $index] $($handle.Description)"
    $h = $handle.Handle

    switch ($Action) {
        'list' {
            Write-Output "    Handle = $h"
        }

        'get' {
            $cur = 0; $max = 0
            if ([DDC]::GetVCPFeatureAndVCPFeatureReply($h, 0x60, [IntPtr]::Zero, [ref]$cur, [ref]$max)) {
                Write-Output ("    VCP 0x60 current = {0}, max = {1}" -f $cur, $max)
            } else {
                Write-Output "    GetVCPFeature failed (31) - monitor does not support DDC/CI or is not the active input"
            }
        }

        'caps' {
            $len = 0
            if ([DDC]::GetCapabilitiesStringLength($h, [ref]$len)) {
                $sb = New-Object System.Text.StringBuilder ([int]$len)
                if ([DDC]::CapabilitiesRequestAndCapabilitiesReply($h, $sb, $len)) {
                    Write-Output "    $($sb.ToString())"
                } else {
                    Write-Output "    Capabilities reply failed"
                }
            } else {
                Write-Output "    GetCapabilitiesStringLength failed"
            }
        }

        'dump' {
            foreach ($dc in $DumpCodes) {
                $cur = 0; $max = 0
                $hex = '0x{0:X2}' -f $dc.Code
                if ([DDC]::GetVCPFeatureAndVCPFeatureReply($h, $dc.Code, [IntPtr]::Zero, [ref]$cur, [ref]$max)) {
                    Write-Output ("    {0} {1,-30} current = {2}, max = {3}" -f $hex, $dc.Name, $cur, $max)
                } else {
                    Write-Output ("    {0} {1,-30} (unreadable)" -f $hex, $dc.Name)
                }
            }
        }

        { $_ -in @('usbc','dp','dp1','dp2','hdmi1','hdmi2') } {
            $target = $InputTargets[$Action]
            if ([DDC]::SetVCPFeature($h, 0x60, [uint32]$target)) {
                Write-Output ("    SetVCPFeature 0x60={0} -> OK" -f $target)
            } else {
                Write-Output ("    SetVCPFeature 0x60={0} -> FAIL (this monitor may not support DDC/CI)" -f $target)
            }
        }

        'set' {
            if ([DDC]::SetVCPFeature($h, 0x60, [uint32]$Value)) {
                Write-Output ("    SetVCPFeature 0x60={0} -> OK" -f $Value)
            } else {
                Write-Output ("    SetVCPFeature 0x60={0} -> FAIL" -f $Value)
            }
        }

        'getcode' {
            $c = Resolve-Code $Code
            $cur = 0; $max = 0
            if ([DDC]::GetVCPFeatureAndVCPFeatureReply($h, $c, [IntPtr]::Zero, [ref]$cur, [ref]$max)) {
                Write-Output ("    VCP 0x{0:X2} current = {1}, max = {2}" -f $c, $cur, $max)
            } else {
                Write-Output ("    GetVCPFeature 0x{0:X2} failed" -f $c)
            }
        }

        'setcode' {
            $c = Resolve-Code $Code
            if ([DDC]::SetVCPFeature($h, $c, [uint32]$Value)) {
                Write-Output ("    SetVCPFeature 0x{0:X2}={1} -> OK" -f $c, $Value)
            } else {
                Write-Output ("    SetVCPFeature 0x{0:X2}={1} -> FAIL" -f $c, $Value)
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Enumerate active HMONITORs, then walk each physical monitor and run action.
# ---------------------------------------------------------------------------
$hmonitors = New-Object System.Collections.ArrayList
$enumCallback = [DDC+MonitorEnumProc] {
    param($hMonitor, $hdcMonitor, [ref]$rect, $data)
    [void]$hmonitors.Add($hMonitor)
    return $true
}

$enumOk = [DDC]::EnumDisplayMonitors([IntPtr]::Zero, [IntPtr]::Zero,
                                     $enumCallback, [IntPtr]::Zero)
if (-not $enumOk) {
    Write-Output "EnumDisplayMonitors failed."
    exit 1
}

if ($hmonitors.Count -eq 0) {
    Write-Output "No active display monitors found."
    exit 1
}

$seq = 0
foreach ($hmon in $hmonitors) {
    $count = 0
    if (-not [DDC]::GetNumberOfPhysicalMonitorsFromHMONITOR($hmon, [ref]$count)) {
        continue
    }
    $arr = New-Object 'DDC+PHYSICAL_MONITOR[]' $count
    if (-not [DDC]::GetPhysicalMonitorsFromHMONITOR($hmon, $count, $arr)) {
        continue
    }

    foreach ($pm in $arr) {
        $seq++
        Invoke-Action ([pscustomobject]@{
            Handle      = $pm.hPhysicalMonitor
            Description = $pm.szPhysicalMonitorDescription
        }) $seq
    }

    [void][DDC]::DestroyPhysicalMonitors($count, $arr)
}

if ($seq -eq 0) {
    Write-Output "No physical monitors could be opened (check the display adapter driver)."
    exit 1
}
