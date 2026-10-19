#requires -Version 5.1
<#
  SwitchToMac.ps1 - One-click switch to the Mac (USB-C input).

  Why this script exists (2026-10-19 hardware finding):
    The U27U2DS needs ~6.5s to cold-start the USB-C port when it has been
    inactive, but its DDC-triggered "no signal" auto-revert fires in ~2-3s,
    so a plain "set 27" while HDMI is still alive gets bounced back.

  Verified workaround (order matters):
    1. Send DDC Input Select = USB-C (27) while HDMI is still the active
       input (this is the only moment the monitor answers DDC).
    2. IMMEDIATELY stop HDMI output (displayswitch /internal). The HDMI
       source disappears before the monitor's auto-revert timer can fire,
       so it stays on USB-C and waits out the cold start.
    3. Wait for the Mac to come up and stabilize (12s).
    4. Restore HDMI output (displayswitch /extend). The screen is already
       locked on the stable Mac image and will NOT jump back.
    5. Windows keeps outputting HDMI in the background, so when the Mac
       later sends m1ddc "set input 18" the switch back to Windows is
       instant. No SSH / network needed.

  Requirements:
    - OSD Extra -> DDC/CI = Yes
    - OSD Input Select = Auto (Auto fallback also helps as a safety net)

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\SwitchToMac.ps1
  Hotkey: point a shortcut (Ctrl+Alt+M) at the matching .bat.
#>

$ErrorActionPreference = "Continue"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ddc = Join-Path $dir "MonitorInput.ps1"

function Wait-Countdown($seconds, $label) {
    for ($i = $seconds; $i -ge 1; $i--) {
        Write-Host ("`r    $label $i s ..." + (" " * 6)) -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ""
}

Write-Host "=== SwitchToMac start ==="

Write-Host "[1/4] Send DDC Input Select = USB-C (27) while HDMI is active ..."
$ddcOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ddc usbc 2>&1
$ddcExitCode = $LASTEXITCODE
$ddcOutput | ForEach-Object { Write-Host $_ }
$ddcText = $ddcOutput -join "`n"
if ($ddcExitCode -ne 0 -or $ddcText -notmatch '(?is)\[Monitor \d+\]\s+(?:AOC[^\r\n]*U27U2DS|U27U2DS)[^\r\n]*[\r\n]+\s+SetVCPFeature 0x60=27 -> OK') {
    Write-Error "DDC switch to USB-C failed on the AOC monitor. HDMI output was left unchanged."
    exit 1
}
Write-Host "    USB-C input selected on the AOC monitor."

Write-Host "[2/4] Immediately stop HDMI output (internal only) to block revert ..."
& displayswitch.exe /internal
if ($LASTEXITCODE -ne 0) {
    Write-Error "Could not switch Windows to internal display mode; aborting."
    exit 1
}
Start-Sleep -Seconds 2

Write-Host "[3/4] Wait for the Mac to come up and stabilize ..."
Wait-Countdown 12 "waiting for Mac"

Write-Host "[4/4] Restore HDMI output (Mac is stable, will not jump back) ..."
& displayswitch.exe /extend
if ($LASTEXITCODE -ne 0) {
    Write-Error "Could not restore extended display mode. Run 'displayswitch.exe /extend' manually."
    exit 1
}
Start-Sleep -Seconds 2

Write-Host "=== Done: screen should stay on the Mac; HDMI is restored in the background. ==="
Write-Host "=== On the Mac, run: m1ddc set input 18  to switch back to Windows. ==="
