#requires -Version 5.1
param([switch]$Install, [string]$Server = "yitaodeMac-mini.local")
$ErrorActionPreference = "Stop"
$dir = Join-Path $env:LOCALAPPDATA "Programs\InputLeap"
$exe = Join-Path $dir "input-leapc.exe"
if (!(Test-Path -LiteralPath $exe)) { throw "InputLeap client missing: $exe" }

function Resolve-ServerIPv4 {
    $addresses = @()
    # .NET Dns.GetHostAddresses drops the mDNS A record for *.local on Windows
    # and returns only the link-local IPv6, so query A records first.
    try {
        $addresses += Resolve-DnsName -Name $Server -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } |
            ForEach-Object { [Net.IPAddress]::Parse($_.IPAddress) }
    } catch {}
    if (!$addresses) {
        try {
            $addresses += [Net.Dns]::GetHostAddresses($Server) |
                Where-Object AddressFamily -eq InterNetwork
        } catch {}
    }
    $address = $addresses | Select-Object -First 1
    if (!$address) { throw "No IPv4 address for $Server" }
    return $address.IPAddressToString
}

if ($Install) {
    if ($Server -notmatch '^[a-zA-Z0-9.-]+$') { throw "Expected a hostname or IPv4 address." }
    # Check name resolution before replacing a running watchdog.
    [void](Resolve-ServerIPv4)
    $name = "InputLeap Client Watchdog"
    $dest = Join-Path $dir "watchdog.ps1"
    if ($PSCommandPath -ne $dest) { Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force }
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument (
        '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Server "{1}"' -f $dest, $Server)
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -User $user -RunLevel Limited -Force | Out-Null
    Stop-ScheduledTask -TaskName $name
    Start-ScheduledTask -TaskName $name
    return
}

$misses = 0
$session = (Get-Process -Id $PID).SessionId
while ($true) {
    try {
        $address = Resolve-ServerIPv4
        $clients = @(Get-Process -Name input-leapc -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $session -and $_.Path -eq $exe })
        $established = Get-NetTCPConnection -RemoteAddress $address -RemotePort 24800 -State Established -ErrorAction SilentlyContinue
        $active = $clients | Where-Object { $_.Id -in $established.OwningProcess } | Select-Object -First 1
        if ($active) {
            $clients | Where-Object Id -ne $active.Id | Stop-Process -Force
            $misses = 0
        } elseif (!$clients.Count -or (++$misses -ge 3)) {
            $clients | Stop-Process -Force
            Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList @(
                "--name", "YT-ASUS-NB", "--disable-crypto", "--restart", "--no-tray", ("${address}:24800"))
            $misses = 0
        }
    } catch {
        Write-Warning $_
    }
    Start-Sleep -Seconds 5
}
