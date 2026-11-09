<#
Run elevated. Binds the MediaTek preloader (0e8d:2000), boot ROM (0e8d:0003), download agent (0e8d:2001), or the Arch USB gadget (18d1:4e23) to usbipd as soon as it appears, then
auto-attaches that USB port to WSL so mtkclient in Linux can talk to it. Writes nothing to the
tablet. Log: C:\mpad26\tools-ext\usbipd-preloader.log. Stops after 30 minutes.
#>
$u = 'C:\Program Files\usbipd-win\usbipd.exe'
$log = 'C:\mpad26\tools-ext\usbipd-preloader.log'
function Log($m) { "$(Get-Date -Format HH:mm:ss.fff) $m" | Add-Content $log }
# Replace any earlier copy of this watcher and its auto-attach process.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'usbipd-preloader' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-CimInstance Win32_Process -Filter "Name='usbipd.exe'" | Where-Object { $_.CommandLine -match 'attach' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Log 'watcher started'
$deadline = (Get-Date).AddMinutes(30); $attachedBus = $null
while ((Get-Date) -lt $deadline) {
  $line = & $u list 2>$null | Where-Object { $_ -match '^\s*(\S+)\s+(0e8d:(2000|0003|2001)|18d1:4e23)' } | Select-Object -First 1
  if ($line -and $line -match '^\s*(\S+)\s') {
    $bus = $Matches[1]
    # usbipd prints 'Not shared' for an unbound device, so test for that exact text.
    if ($line -match 'Not shared') { & $u bind --busid $bus 2>&1 | ForEach-Object { Log "bind: $_" }; Log "bound $bus" }
    if ($attachedBus -ne $bus) {
      Start-Process $u -ArgumentList "attach --wsl --auto-attach --busid $bus" -WindowStyle Hidden
      Log "auto-attach started for $bus"; $attachedBus = $bus
    }
  }
  Start-Sleep -Milliseconds 150
}
Log 'watcher stopped'
