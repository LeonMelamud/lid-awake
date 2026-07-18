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

# session id from the hook's stdin JSON (skip when run manually from a tty);
# fall back to the parent pid so manual runs still refcount distinctly
SID=""
if [ ! -t 0 ]; then
  SID=$(python3 -c 'import sys,json;print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)
fi
[ -n "$SID" ] || SID="pid$PPID"
SID=${SID:0:8}

log(){ echo "$(date '+%F %T') sid=$SID $*" >> "$LOG"; }

# prune stale flags (crashed/killed sessions) so the mac can't stay awake forever
# ponytail: 12h mtime cutoff; flags are re-touched on every prompt, so a live
# session never goes stale — only a dead one does
find "$DIR" -type f -mmin +720 -delete 2>/dev/null

case "$1" in
  on)
    touch "$DIR/$SID"
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
