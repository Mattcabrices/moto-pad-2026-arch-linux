<#
Asks the MediaTek preloader to boot into fastboot. Nothing is written to the tablet's storage:
the preloader shows up as a USB COM port for a few seconds at power-on, and sending the text
"FASTBOOT" in that window selects the boot mode for this one boot.

Usage: run this, then power the tablet on (or plug it in while off). Waits up to 10 minutes.
#>
$ErrorActionPreference = 'Continue'
$Fb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\fastboot.exe'
$baseline = [System.IO.Ports.SerialPort]::GetPortNames()
"Waiting for the preloader port. Existing ports: $($baseline -join ', ')"
$deadline = (Get-Date).AddMinutes(10)
while ((Get-Date) -lt $deadline) {
  $new = [System.IO.Ports.SerialPort]::GetPortNames() | Where-Object { $baseline -notcontains $_ }
  foreach ($port in $new) {
    "$(Get-Date -Format HH:mm:ss.fff) new port $port, sending FASTBOOT"
    $sp = New-Object System.IO.Ports.SerialPort $port, 115200, 'None', 8, 'One'
    $sp.ReadTimeout = 50; $sp.WriteTimeout = 200
    $got = ''
    try {
      # The port appears before its driver is ready, so keep retrying the open while it exists.
      $openBy = (Get-Date).AddSeconds(6)
      while (-not $sp.IsOpen -and (Get-Date) -lt $openBy) {
        try { $sp.Open() } catch {
          if ([System.IO.Ports.SerialPort]::GetPortNames() -notcontains $port) { throw "port $port went away before it could be opened" }
          Start-Sleep -Milliseconds 40
        }
      }
      if (-not $sp.IsOpen) { throw "could not open $port within 6 s" }
      "$(Get-Date -Format HH:mm:ss.fff) opened $port"
      $t = (Get-Date).AddSeconds(4)
      while ((Get-Date) -lt $t -and $sp.IsOpen) {
        try { $sp.Write('FASTBOOT') } catch { break }
        Start-Sleep -Milliseconds 30
        try { $got += $sp.ReadExisting() } catch {}
        if ($got -match 'READY|FASTBOOT') { break }
      }
    } catch { "open failed: $($_.Exception.Message)" }
    finally { if ($sp.IsOpen) { $sp.Close() } }
    "reply: '$($got -replace '[^\x20-\x7e]', '.')'"
    $baseline = [System.IO.Ports.SerialPort]::GetPortNames()
  }
  if ((& $Fb devices 2>&1 | Out-String).Trim()) { "FASTBOOT READY $(Get-Date -Format HH:mm:ss)"; break }
  Start-Sleep -Milliseconds 100
}
