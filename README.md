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

## Install (fast — as a Claude Code plugin)

The repo is a self-hosting plugin: hooks are registered automatically, no settings.json editing.

1. In Claude Code:

   ```
   /plugin marketplace add LeonMelamud/lid-awake
   /plugin install lid-awake@lid-awake
   ```

2. Allow the two exact `pmset` commands without a password (one-time, the only manual step — no plugin can or should automate sudoers):

   ```bash
   echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0" \
     | sudo tee /etc/sudoers.d/lid-awake >/dev/null && sudo chmod 440 /etc/sudoers.d/lid-awake \
     && sudo visudo -c
   ```

   The final `visudo -c` must print "parsed OK" — a malformed sudoers file can break `sudo` itself, so if it complains, remove the file (`sudo rm /etc/sudoers.d/lid-awake`) and retry.

Done. Verify with `bash lid-awake.sh status` after your next prompt.

## Install (manual, without the plugin system)

1. Copy the script:

   ```bash
   mkdir -p ~/.claude/scripts
   cp lid-awake.sh ~/.claude/scripts/lid-awake.sh
   ```

2. Add the sudoers entry from step 2 above.

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

## Tests & security checks

```bash
bash test.sh        # 10 assertions: refcounting, stale pruning, clear — stubs sudo, no root needed
shellcheck *.sh     # static analysis
```

CI (`.github/workflows/ci.yml`) runs shellcheck + tests and a [gitleaks](https://github.com/gitleaks/gitleaks) secret scan on every push. Snyk was skipped on purpose: it scans package dependencies and this repo has none — shellcheck is the SAST tool for shell.

## Requirements

- macOS (`pmset` — everything the script uses ships with the OS, nothing to install)
- An admin account (for the one-time sudoers entry)
- A recent Claude Code (plugin marketplace support; for the manual route, hooks support is enough)
