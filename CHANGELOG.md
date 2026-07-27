# Changelog

All notable changes to lid-awake are documented here. Versions follow the
`version` field in `.claude-plugin/plugin.json`.

## [1.2.0]

- Network guard: with no default route (Wi-Fi off and nothing else up) the
  hold is skipped — Claude can't work offline. Connected-but-weak keeps the
  hold, since a bad signal often recovers.
- Guards now release the session's own hold instead of only skipping the new
  one, so a guard tripping mid-session can't leave the machine pinned awake.

## [1.1.1]

- Cursor support: the script accepts `conversation_id` as well as `session_id`,
  so Cursor IDE sessions refcount together with Claude Code sessions.
- README guides for Cursor and GitHub Copilot integration.

## [1.1.0]

- Battery guard: below 20% on battery power, new sleep-holds are skipped and
  self-heal on the next prompt once charging or above the threshold.
- Transcript-based crash cleanup: a flag whose session transcript has been
  stale for 30 min is dropped at the next event from any session; a 12h
  flag-age prune backstops flags with no transcript.
- Experimental Windows port under `windows/` (powercfg + scheduled tasks).

## [1.0.0]

- Initial release: keep a Mac awake (lid closed or not) while any Claude Code
  session is working, re-enabling sleep when the last session finishes.
- Multi-session refcounting via one empty flag file per live session in
  `.lid-awake-flags/`; O(1) `touch`/`rm` per hook event.
- `status` / `clear` subcommands; self-truncating log.
