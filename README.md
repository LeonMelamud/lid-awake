# lid-awake

Keep a MacBook awake (lid closed or not) while any Claude Code session is working, and re-enable sleep the moment the **last** session finishes. Multi-session safe, O(1) per event, no daemons, no polling.

## How it works

Claude Code hooks call the script on session activity:

| Hook | Call | Effect |
|------|------|--------|
| `UserPromptSubmit` | `lid-awake.sh on` | touch `.lid-awake-flags/<session_id>`, `pmset -a disablesleep 1` |
| `Stop` / `SessionEnd` | `lid-awake.sh off` | remove the flag; if the flags dir is empty → `disablesleep 0` |

The flag **directory** is the real-time state: one empty file per live session. `touch`/`rm` are O(1); sleep is only re-enabled when the last holder leaves. A single 0/1 flag file was considered and rejected — it can't refcount, so the first session to stop would re-enable sleep under a second still-working session (that was the original bug).

Safety nets:

- **Stale flags** from crashed/killed sessions are pruned after 12h of no touch (flags are re-touched on every prompt, so only dead sessions go stale).
- **Log** at `~/.claude/scripts/lid-awake.log`, self-truncated at ~200KB.
- `status` / `clear` subcommands for debugging and manual unstick.

## Install

1. Copy the script:

   ```bash
   mkdir -p ~/.claude/scripts
   cp lid-awake.sh ~/.claude/scripts/lid-awake.sh
   ```

2. Allow the two exact `pmset` commands without a password (`sudo visudo`, or a file in `/etc/sudoers.d/`):

   ```
   yourusername ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
   ```

3. Wire the hooks in `~/.claude/settings.json`:

   ```json
   {
     "hooks": {
       "UserPromptSubmit": [
         { "hooks": [{ "type": "command", "command": "bash ~/.claude/scripts/lid-awake.sh on", "async": true }] }
       ],
       "Stop": [
         { "hooks": [{ "type": "command", "command": "bash ~/.claude/scripts/lid-awake.sh off", "async": true }] }
       ],
       "SessionEnd": [
         { "hooks": [{ "type": "command", "command": "bash ~/.claude/scripts/lid-awake.sh off", "async": true }] }
       ]
     }
   }
   ```

## Debugging

```bash
bash ~/.claude/scripts/lid-awake.sh status   # pmset state + current holders + log tail
bash ~/.claude/scripts/lid-awake.sh clear    # drop all flags, re-enable sleep
```

## Requirements

- macOS (`pmset`)
- Claude Code with hooks support
- `python3` (parses the hook JSON for the session id; falls back to parent PID)
