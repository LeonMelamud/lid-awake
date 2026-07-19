#!/bin/bash
# Toggle macOS lid-close sleep, multi-session safe. Needs the NOPASSWD sudoers
# entry for the two exact pmset commands.
#
# on/off are called by Claude Code hooks (UserPromptSubmit / Stop / SessionEnd)
# and receive the hook JSON on stdin — the session_id becomes a flag file in
# $DIR, and sleep is only re-enabled when the LAST holder releases (fixes the
# old single-session assumption: one session stopping used to re-enable sleep
# while another was still mid-task).
#
# Debugging:  bash lid-awake.sh status   # pmset state + holders + log tail
#             bash lid-awake.sh clear    # unstick: drop all flags, re-enable sleep
#             log: ~/.claude/scripts/lid-awake.log (who slept/woke, when, why)
DIR="$HOME/.claude/scripts/.lid-awake-flags"
LOG="$HOME/.claude/scripts/lid-awake.log"
mkdir -p "$DIR"

# session id + transcript path from the hook's stdin JSON (skip when run
# manually from a tty); fall back to the parent pid so manual runs still
# refcount distinctly. sed, not python3: stock on every Mac, and python3
# without Xcode CLT pops a GUI install dialog — fatal from a background hook
IN="" SID="" TP=""
if [ ! -t 0 ]; then
  IN=$(cat)
  SID=$(printf '%s' "$IN" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  TP=$(printf '%s' "$IN" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
fi
[ -n "$SID" ] || SID="pid$PPID"
SID=${SID:0:8}

log(){ echo "$(date '+%F %T') sid=$SID $*" >> "$LOG"; }

# crash cleanup: each flag stores its session's transcript path. A session
# that is actually working appends to its transcript constantly, so a
# transcript untouched for 30 min means the session is dead — drop its flag
# at the next event from ANY session. 12h flag-mtime cutoff stays as the
# backstop for flags with no readable transcript (manual runs, legacy).
for f in "$DIR"/*; do
  [ -f "$f" ] || continue
  tp=$(head -n1 "$f" 2>/dev/null)
  if [ -n "$tp" ] && [ -f "$tp" ] && [ -n "$(find "$tp" -mmin +30 2>/dev/null)" ]; then
    rm -f "$f"
    log "pruned $(basename "$f") (transcript stale >30m, session dead)"
  fi
done
find "$DIR" -type f -mmin +720 -delete 2>/dev/null

case "$1" in
  on)
    # ponytail: below 20% on battery, don't pin the Mac awake — closed-bag
    # drain/heat guard. Self-heals: next prompt re-checks, so plugging in
    # (or charging back over 20%) re-enables the hold automatically.
    BATT=$(pmset -g batt 2>/dev/null)
    if printf '%s' "$BATT" | grep -q "Battery Power"; then
      PCT=$(printf '%s' "$BATT" | grep -o '[0-9]\{1,3\}%' | head -n1 | tr -d '%')
      if [ -n "$PCT" ] && [ "$PCT" -lt 20 ]; then
        log "on  -> LOW BATTERY ${PCT}%, not holding (sleep stays enabled)"
        exit 0
      fi
    fi
    printf '%s\n' "$TP" > "$DIR/$SID"
    sudo -n /usr/bin/pmset -a disablesleep 1 2>/dev/null
    log "on  -> disablesleep=1 holders=[$(ls -m "$DIR" 2>/dev/null)]"
    ;;
  off)
    rm -f "$DIR/$SID"
    if [ -z "$(ls "$DIR" 2>/dev/null)" ]; then
      sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null
      log "off -> disablesleep=0 (last holder out)"
    else
      log "off -> KEPT AWAKE, other sessions active: [$(ls -m "$DIR")]"
    fi
    ;;
  status)
    echo "pmset : $(pmset -g 2>/dev/null | grep -i sleepdisabled | tr -s ' ')"
    echo "holders: $(ls -m "$DIR" 2>/dev/null)"
    echo "--- last 10 log lines ---"
    tail -n 10 "$LOG" 2>/dev/null
    ;;
  clear)
    rm -f "$DIR"/*
    sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null
    log "clear -> disablesleep=0 (manual reset)"
    ;;
esac

# keep the log bounded (~200KB -> keep last 500 lines)
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 200000 ]; then
  tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
exit 0
