# One-time setup — run in an ELEVATED PowerShell (Run as Administrator).
# Registers two scheduled tasks that run lid-awake.ps1's privileged halves
# with highest privileges, so the user-level Claude Code hook can toggle
# power settings without UAC prompts. Mirror of the macOS sudoers entry.
#Requires -RunAsAdministrator

$script = Join-Path $PSScriptRoot "lid-awake.ps1"
if (-not (Test-Path $script)) { throw "lid-awake.ps1 not found next to setup.ps1" }

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
  -RunLevel Highest -LogonType Interactive

foreach ($mode in "on", "off") {
  $action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`" apply-$mode"
  Register-ScheduledTask -TaskName "lid-awake-apply-$mode" -Action $action `
    -Principal $principal -Force | Out-Null
  Write-Host "registered task: lid-awake-apply-$mode"
}
Write-Host "Done. Test with:  schtasks /Run /TN lid-awake-apply-on  then  powershell -File `"$script`" status"
