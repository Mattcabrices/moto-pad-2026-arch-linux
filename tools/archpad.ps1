<#
Moto Pad Arch tool. Run from the project folder in Windows PowerShell.

  .\tools\archpad.ps1 preflight            Read-only checks in fastboot mode
  .\tools\archpad.ps1 testboot             Boots Arch once from RAM. Writes nothing to the tablet.
  .\tools\archpad.ps1 flash -IUnderstandThisWipesAndroid
                                           Writes userdata (wipes Android data) and boot_a
  .\tools\archpad.ps1 restore -IUnderstandThisWipesArch
                                           Writes stock boot_a and erases userdata and metadata
  .\tools\archpad.ps1 ssh                  SSH to the tablet over USB (10.55.0.1)
  .\tools\archpad.ps1 rescue               Shell on the early-boot debug console (port 23)

Only boot_a, userdata, and metadata are ever written. Never lk, preloader, or slot B.
#>
param(
  [Parameter(Mandatory)][ValidateSet('preflight','testboot','flash','restore','ssh','rescue')][string]$Action,
  [switch]$IUnderstandThisWipesAndroid,
  [switch]$IUnderstandThisWipesArch
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Out = Join-Path $Root 'out'
$Fb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\fastboot.exe'
$StockBoot = 'C:\Edge 26\motopad-2026\recovery-diagnostics\stock-020-chain\boot.img'
$StockBootSha = '6e287551452f0a3a7957d34e629dbc015c20a3c96b337309e4ea8ff9b47e3515'

function Fastboot([string[]]$a) {
  # fastboot reports on stderr; Windows PowerShell 5.1 turns that into errors under 'Stop'.
  $ErrorActionPreference = 'Continue'
  $r = & $Fb @a 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) { throw "fastboot $($a -join ' ') failed:`n$($r -join "`n")" }
  return ($r -join "`n")
}
function Get-PadVar([string]$n) {
  # Only these getvars are used. 'oem device-info' and 'version-baseband' wedge this bootloader.
  $t = Fastboot @('getvar', $n)
  if ($t -match "(?m)^$([regex]::Escape($n)):\s*(\S+)") { return $Matches[1] }
  throw "Could not read $n from:`n$t"
}
function Preflight {
  if (-not (Test-Path $Fb)) { throw "fastboot not found at $Fb" }
  $dev = (& $Fb devices 2>&1 | Out-String).Trim()
  if (-not $dev) { throw 'No device in fastboot mode. Run: adb reboot bootloader' }
  $p = Get-PadVar 'product'; $s = Get-PadVar 'current-slot'; $u = Get-PadVar 'unlocked'
  "product=$p  current-slot=$s  unlocked=$u"
  if ($p -ne 'sycamore_row_5G') { throw "STOP: product is $p, expected sycamore_row_5G" }
  if ($s -ne 'a') { throw "STOP: active slot is $s; this project only uses slot a" }
  if ($u -ne 'yes') { throw 'STOP: bootloader is not unlocked' }
  'Preflight OK.'
}
function CheckHash([string]$file, [string]$want) {
  $h = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $want.ToLower()) { throw "STOP: hash mismatch for $file" }
}
function CheckOut {
  foreach ($l in Get-Content (Join-Path $Out 'SHA256SUMS.txt')) {
    $want, $name = $l -split '\s+', 2
    CheckHash (Join-Path $Out $name.TrimStart('*')) $want
  }
  'Image hashes OK.'
}

switch ($Action) {
  'preflight' { Preflight }
  'testboot' {
    Preflight; CheckOut
    'Booting Arch from RAM. Nothing is written. If userdata is still Android, the tablet'
    'holds at a debug console; run: .\tools\archpad.ps1 rescue'
    Fastboot @('boot', (Join-Path $Out 'boot-archpad.img'))
  }
  'flash' {
    if (-not $IUnderstandThisWipesAndroid) { throw 'Refusing: add -IUnderstandThisWipesAndroid' }
    Preflight; CheckOut
    Fastboot @('flash', 'userdata', (Join-Path $Out 'userdata-archpad.simg'))
    Fastboot @('flash', 'boot_a', (Join-Path $Out 'boot-archpad.img'))
    Fastboot @('reboot')
    'Flashed. First boot grows the filesystem; then: .\tools\archpad.ps1 ssh'
  }
  'restore' {
    if (-not $IUnderstandThisWipesArch) { throw 'Refusing: add -IUnderstandThisWipesArch' }
    Preflight; CheckHash $StockBoot $StockBootSha
    Fastboot @('flash', 'boot_a', $StockBoot)
    Fastboot @('erase', 'userdata')
    Fastboot @('erase', 'metadata')
    Fastboot @('reboot')
    'Stock boot restored and Arch erased. Android formats data on first start; if it opens'
    'recovery instead, choose Factory reset.'
  }
  'ssh' {
    $kh = Join-Path $Out 'known_hosts'
    ssh -i (Join-Path $Out 'archpad_ed25519') -o "UserKnownHostsFile=$kh" -o StrictHostKeyChecking=accept-new matt@10.55.0.1
  }
  'rescue' { python -I (Join-Path $PSScriptRoot 'padshell.py') 10.55.0.1 23 }
}
