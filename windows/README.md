# lid-awake for Windows

> ⚠️ **EXPERIMENTAL** — same design as the macOS version, but not yet tested on real Windows hardware. If you try it, please open an issue with the result.

Keeps a Windows laptop awake — lid closed too — while any Claude Code session is working, and restores your power settings when the last session finishes.

## How it works

Windows has no `pmset`; lid-close sleep is a power-plan setting. On first-in the script saves your current lid action + standby timeouts, sets lid action to *do nothing* and standby to *never*; on last-out it restores what you had. Changing power settings needs admin, so a one-time `setup.ps1` (run elevated) registers two scheduled tasks that run the privileged half with highest privileges — the user-level hook just triggers them, no UAC prompts. This is the Windows mirror of the macOS sudoers entry.

Same safety nets as macOS: per-session flag refcounting, 12h stale-flag prune, low-battery guard (below 20% and discharging it won't hold), bounded log.

## Install

1. Copy the two scripts:

   ```powershell
   New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\scripts" | Out-Null
   Copy-Item lid-awake.ps1, setup.ps1 "$env:USERPROFILE\.claude\scripts\"
   ```

2. One-time, in an **elevated** PowerShell (Run as Administrator):

   ```powershell
   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\setup.ps1"
   ```

3. Wire the hooks in `%USERPROFILE%\.claude\settings.json` (replace `YOU`):

   ```json
   {
     "hooks": {
       "UserPromptSubmit": [
         { "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\YOU\\.claude\\scripts\\lid-awake.ps1\" on", "async": true }] }
       ],
       "Stop": [
         { "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\YOU\\.claude\\scripts\\lid-awake.ps1\" off", "async": true }] }
       ],
       "SessionEnd": [
         { "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\YOU\\.claude\\scripts\\lid-awake.ps1\" off", "async": true }] }
       ]
     }
   }
   ```

## Debugging

```powershell
powershell -File "$env:USERPROFILE\.claude\scripts\lid-awake.ps1" status   # power state + holders + log tail
powershell -File "$env:USERPROFILE\.claude\scripts\lid-awake.ps1" clear    # unstick: drop flags, restore power settings
```

## Known limitations

- `powercfg /query` output parsing is position-based (last two hex values = AC/DC); on exotic locales it may fail — the script then restores sane defaults (lid = sleep, standby 30/15 min) instead of your exact previous values.
- No transcript-based crash detection yet (macOS has it); crashes fall back to the 12h prune.
- Closing the lid may still disconnect Wi-Fi on some machines ("Modern Standby" / connected standby laptops behave differently than classic S3 sleep).
