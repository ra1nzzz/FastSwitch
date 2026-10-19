@echo off
REM ============================================================
REM  SwitchToMac.bat - Switch the AOC U27U2DS to the Mac (USB-C).
REM
REM  Sequence: send DDC select USB-C -> stop HDMI -> wait 12s ->
REM            restore HDMI so switching back is instant.
REM
REM  Zero third-party dependencies (uses MonitorInput.ps1 / dxva2).
REM
REM  Hotkey: right-click this file -> Create shortcut ->
REM          right-click the shortcut -> Properties -> Shortcut key
REM          (e.g. Ctrl+Alt+M)
REM ============================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SwitchToMac.ps1"
echo.
echo Done. This window closes in 3 seconds.
timeout /t 3 >nul
