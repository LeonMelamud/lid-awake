# lid-awake

![Closed MacBook still glowing while the moon dissolves — Claude keeps working](assets/banner.png)

Keep a MacBook awake (lid closed or not) while any Claude Code session is working, and re-enable sleep the moment the **last** session finishes. Multi-session safe, O(1) per event, no daemons, no polling.

## How it works

Claude Code hooks call the script on session activity:

| Hook | Call | Effect |
|------|------|--------|
| `UserPromptSubmit` | `lid-awake.sh on` | touch `.lid-awake-flags/<session_id>`, `pmset -a disablesleep 1` |
| `Stop` / `SessionEnd` | `lid-awake.sh off` | remove the flag; if the flags dir is empty → `disablesleep 0` |

The flag **directory** is the real-time state: one empty file per live session. `touch`/`rm` are O(1); sleep is only re-enabled when the last holder leaves. A single 0/1 flag file was considered and rejected — it can't refcount, so the first session to stop would re-enable sleep under a second still-working session (that was the original bug).

Safety nets:

- **Crash cleanup** — each flag records its session's transcript path; a working session updates its transcript constantly, so a transcript stale for 30 min marks a dead session and its flag is dropped at the next event from any session. A 12h flag-age prune backstops flags with no transcript.
- **Battery guard** — below 20% on battery power, new holds are skipped (no cooked Mac in a closed bag); self-heals on the next prompt once charging or above the threshold.
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

## Cursor

Same script, Cursor's own hooks — and Cursor + Claude Code sessions refcount together, since they share the flag directory.

1. Copy the script and add the sudoers entry (steps 1–2 of the manual install above).
2. Add to `~/.cursor/hooks.json` (absolute path — replace `YOU`):

   ```json
   {
     "version": 1,
     "hooks": {
       "beforeSubmitPrompt": [{ "command": "bash /Users/YOU/.claude/scripts/lid-awake.sh on" }],
       "stop": [{ "command": "bash /Users/YOU/.claude/scripts/lid-awake.sh off" }]
     }
   }
   ```

Cursor sends `conversation_id` instead of `session_id`; the script accepts either. Two caveats: Cursor's hook JSON has no transcript path, so crash cleanup for Cursor sessions falls back to the 12h prune; and the Cursor *CLI* currently emits only shell-execution hook events, so this works in the Cursor IDE only.

## Copilot & anything else

GitHub Copilot needs no integration: its coding agent runs in GitHub's cloud, so your laptop sleeping doesn't affect it — and Copilot in VS Code exposes no lifecycle hooks to attach to. For any other tool (or none), drive it by hand around long jobs:

```bash
bash ~/.claude/scripts/lid-awake.sh on    # hold (refcounts alongside Claude Code/Cursor)
bash ~/.claude/scripts/lid-awake.sh off   # release
```

## Windows

An experimental Windows port (powercfg lid-action toggle + elevated scheduled tasks instead of pmset + sudoers) lives in [`windows/`](windows/) — see its README. Untested on real hardware; testers welcome.

## Requirements

- macOS (`pmset` — everything the script uses ships with the OS, nothing to install)
- An admin account (for the one-time sudoers entry)
- A recent Claude Code (plugin marketplace support; for the manual route, hooks support is enough)

## License

MIT — see [LICENSE](LICENSE). Free to use, fork, and share.

## Support

lid-awake is free and open source. If it saved you a cooked laptop or a drained
battery, you can [sponsor the project](https://github.com/sponsors/LeonMelamud) —
entirely optional, and it stays free either way.
