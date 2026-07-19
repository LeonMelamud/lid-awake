# lid-awake for Windows — EXPERIMENTAL, not yet tested on real hardware.
# Same design as the macOS script: one flag file per Claude Code session,
# power settings only touched on first-in / last-out.
#
# Windows has no pmset; lid-close sleep is a power-plan setting (LIDACTION).
# Changing it needs admin, so setup.ps1 (run once, elevated) registers two
# scheduled tasks that run the privileged apply-on/apply-off halves of this
# script with highest privileges; the user-level hook just triggers them —
# the Windows mirror of the macOS sudoers entry.
#
# Commands: on | off | status | clear   (called by Claude Code hooks / user)
#           apply-on | apply-off        (called only by the scheduled tasks)
param([Parameter(Position = 0)][string]$Cmd = "status")

$Base  = Join-Path $env:USERPROFILE ".claude\lid-awake"
$Dir   = Join-Path $Base "flags"
$Log   = Join-Path $Base "lid-awake.log"
$Saved = Join-Path $Base "saved-power.json"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

function Log([string]$m) {
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content -Path $Log
  if ((Get-Item $Log -ErrorAction SilentlyContinue).Length -gt 200KB) {
    Get-Content $Log -Tail 500 | Set-Content $Log
  }
}

# last two 0x......... values in a powercfg /query block are the AC and DC indexes
function Get-PowerValues([string]$sub, [string]$setting) {
  $q = powercfg /query SCHEME_CURRENT $sub $setting 2>$null
  $hex = ($q | Select-String -Pattern '0x[0-9a-fA-F]{8}' -AllMatches).Matches.Value
  if ($hex.Count -ge 2) {
    return @([Convert]::ToInt32($hex[-2], 16), [Convert]::ToInt32($hex[-1], 16))
  }
  return $null
}

# ---- privileged half: runs elevated via the setup.ps1 scheduled tasks ----
if ($Cmd -eq "apply-on") {
  if (-not (Test-Path $Saved)) {
    $lid = Get-PowerValues "SUB_BUTTONS" "LIDACTION"
    $sby = Get-PowerValues "SUB_SLEEP" "STANDBYIDLE"
    if (-not $lid) { $lid = @(1, 1) }        # parse failed (locale?) -> assume default: sleep
    if (-not $sby) { $sby = @(1800, 900) }   # seconds; defaults 30/15 min
    @{ lidAc = $lid[0]; lidDc = $lid[1]; sbyAc = $sby[0]; sbyDc = $sby[1] } |
      ConvertTo-Json | Set-Content $Saved
  }
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /change standby-timeout-ac 0
  powercfg /change standby-timeout-dc 0
  powercfg /setactive SCHEME_CURRENT
  Log "apply-on  -> lid action = do nothing, standby = never"
  exit 0
}
if ($Cmd -eq "apply-off") {
  $s = if (Test-Path $Saved) { Get-Content $Saved -Raw | ConvertFrom-Json } else { $null }
  $lidAc = if ($s) { $s.lidAc } else { 1 }
  $lidDc = if ($s) { $s.lidDc } else { 1 }
  $sbyAc = if ($s) { [int]($s.sbyAc / 60) } else { 30 }
  $sbyDc = if ($s) { [int]($s.sbyDc / 60) } else { 15 }
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION $lidAc
  powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION $lidDc
  powercfg /change standby-timeout-ac $sbyAc
  powercfg /change standby-timeout-dc $sbyDc
  powercfg /setactive SCHEME_CURRENT
  Remove-Item $Saved -Force -ErrorAction SilentlyContinue
  Log "apply-off -> restored lid=$lidAc/$lidDc standby=$sbyAc/${sbyDc}min"
  exit 0
}

# ---- user half: flags + refcount, mirrors the macOS script ----
$sid = ""
if ([Console]::IsInputRedirected) {
  try { $sid = ([Console]::In.ReadToEnd() | ConvertFrom-Json).session_id } catch {}
}
if (-not $sid) { $sid = "pid$PID" }
if ($sid.Length -gt 8) { $sid = $sid.Substring(0, 8) }

# stale prune: crashed sessions can't hold the machine awake past 12h
Get-ChildItem $Dir -File -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-12) } |
  Remove-Item -Force

function Holders { (Get-ChildItem $Dir -File -ErrorAction SilentlyContinue).Name -join ', ' }

switch ($Cmd) {
  "on" {
    # battery guard: below 20% and discharging -> don't pin the machine awake
    $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if ($b -and $b.BatteryStatus -eq 1 -and $b.EstimatedChargeRemaining -lt 20) {
      Log "on  sid=$sid -> LOW BATTERY $($b.EstimatedChargeRemaining)%, not holding"
      break
    }
    New-Item -ItemType File -Force -Path (Join-Path $Dir $sid) | Out-Null
    schtasks /Run /TN "lid-awake-apply-on" | Out-Null
    Log "on  sid=$sid -> holders=[$(Holders)]"
  }
  "off" {
    Remove-Item (Join-Path $Dir $sid) -Force -ErrorAction SilentlyContinue
    if (-not (Get-ChildItem $Dir -File -ErrorAction SilentlyContinue)) {
      schtasks /Run /TN "lid-awake-apply-off" | Out-Null
      Log "off sid=$sid -> restored (last holder out)"
    }
    else {
      Log "off sid=$sid -> KEPT AWAKE, other sessions: [$(Holders)]"
    }
  }
  "status" {
    "lid action (last two hex = AC/DC; 0 = do nothing):"
    powercfg /query SCHEME_CURRENT SUB_BUTTONS LIDACTION | Select-String '0x[0-9a-fA-F]{8}'
    "holders: $(Holders)"
    "--- last 10 log lines ---"
    Get-Content $Log -Tail 10 -ErrorAction SilentlyContinue
  }
  "clear" {
    Get-ChildItem $Dir -File -ErrorAction SilentlyContinue | Remove-Item -Force
    schtasks /Run /TN "lid-awake-apply-off" | Out-Null
    Log "clear -> restored (manual reset)"
  }
}
