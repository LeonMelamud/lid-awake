#!/bin/bash
# Self-contained test for lid-awake.sh — no framework, no root.
# Stubs `sudo` and `pmset` via PATH (privileged pmset goes through `sudo -n
# /usr/bin/pmset`, battery reads go through plain `pmset`) and points HOME at
# a temp dir so flags/log are isolated.
set -u
SCRIPT="$(cd "$(dirname "$0")" && pwd)/lid-awake.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
# fake sudo: record the pmset args instead of running them
cat > "$TMP/bin/sudo" <<EOF
#!/bin/bash
echo "\$*" >> "$TMP/sudo.calls"
EOF
# fake pmset: `-g batt` reports FAKE_SRC / FAKE_PCT, bare `-g` reports
# SleepDisabled from FAKE_SLEEPDISABLED (what `reap` reads)
cat > "$TMP/bin/pmset" <<'EOF'
#!/bin/bash
case "$*" in
  *batt*)
    echo "Now drawing from '${FAKE_SRC:-AC Power}'"
    echo " -InternalBattery-0 (id=123)	${FAKE_PCT:-100}%; charging; 2:00 remaining" ;;
  *) echo " SleepDisabled		${FAKE_SLEEPDISABLED:-1}" ;;
esac
EOF
# fake pgrep: no claude process when FAKE_CLAUDE=none
cat > "$TMP/bin/pgrep" <<'EOF'
#!/bin/bash
[ "${FAKE_CLAUDE:-up}" = none ] && exit 1
echo 12345
EOF
# fake route: default route exists unless FAKE_NET=off (Wi-Fi off / no link)
cat > "$TMP/bin/route" <<'EOF'
#!/bin/bash
[ "${FAKE_NET:-on}" = off ] && exit 1
echo "  interface: en0"
EOF
chmod +x "$TMP/bin/sudo" "$TMP/bin/pmset" "$TMP/bin/route" "$TMP/bin/pgrep"
export PATH="$TMP/bin:$PATH" HOME="$TMP"
FLAGS="$TMP/.claude/scripts/.lid-awake-flags"

run(){ printf '{"session_id":"%s"}' "$1" | bash "$SCRIPT" "$2"; }
last_call(){ tail -n1 "$TMP/sudo.calls" 2>/dev/null; }
ago(){ # ago <minutes> -> touch timestamp for BSD or GNU date
  date -v-"$1"M '+%Y%m%d%H%M' 2>/dev/null || date -d "$1 minutes ago" '+%Y%m%d%H%M'
}

fail=0
check(){ # check <desc> <condition...>
  local desc="$1"; shift
  if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; fail=1; fi
}

# 1. first session on -> flag created, sleep disabled
run aaaa1111 on
check "on creates flag"            test -f "$FLAGS/aaaa1111"
check "on disables sleep"          grep -q "disablesleep 1" "$TMP/sudo.calls"

# 2. second session on -> two holders
run bbbb2222 on
check "two holders"                test "$(find "$FLAGS" -type f | wc -l)" -eq 2

# 3. first session off -> still one holder, sleep must NOT be re-enabled
: > "$TMP/sudo.calls"
run aaaa1111 off
check "off removes own flag"       test ! -f "$FLAGS/aaaa1111"
check "kept awake while B active"  test ! -s "$TMP/sudo.calls"

# 4. last session off -> sleep re-enabled
run bbbb2222 off
check "last off re-enables sleep"  test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 0"
check "flags dir empty"            test -z "$(ls "$FLAGS")"

# 5. flag with no transcript (>12h old) pruned by the mtime backstop
touch "$FLAGS/deadsess"
touch -t "$(ago 780)" "$FLAGS/deadsess"
run cccc3333 on
check "12h backstop prunes"        test ! -f "$FLAGS/deadsess"
run cccc3333 off

# 6. crashed session: flag whose transcript went stale >30m is pruned
touch "$TMP/tr-dead.jsonl"; touch -t "$(ago 45)" "$TMP/tr-dead.jsonl"
echo "$TMP/tr-dead.jsonl" > "$FLAGS/deadtr11"
touch "$TMP/tr-live.jsonl"
echo "$TMP/tr-live.jsonl" > "$FLAGS/livetr22"
run dddd4444 on
check "stale transcript pruned"    test ! -f "$FLAGS/deadtr11"
check "fresh transcript kept"      test -f "$FLAGS/livetr22"
rm -f "$FLAGS/livetr22"; run dddd4444 off

# 7. battery guard: below 20% on battery -> no hold, sleep left enabled
: > "$TMP/sudo.calls"
FAKE_SRC="Battery Power" FAKE_PCT=15 run lowb5555 on
check "low battery: no flag"       test ! -f "$FLAGS/lowb5555"
check "low battery: sleep on"      test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 0"
FAKE_SRC="Battery Power" FAKE_PCT=55 run okba6666 on
check "55% battery: holds"         test -f "$FLAGS/okba6666"
run okba6666 off

# 7b. network guard: no default route -> no hold; weak-but-connected still holds
FAKE_NET=off run nonet777 on
check "no network: no flag"        test ! -f "$FLAGS/nonet777"
check "no network: sleep on"       test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 0"
run wifi8888 on
check "network up: holds"          test -f "$FLAGS/wifi8888"
# guard trips mid-hold -> existing hold is released, not left pinned
FAKE_NET=off run wifi8888 on
check "net drop releases hold"     test ! -f "$FLAGS/wifi8888"
check "net drop re-enables sleep"  test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 0"
# ...but only when it was the last holder
run keep9999 on
FAKE_NET=off run wifi8888 on
check "other holder kept awake"    test -f "$FLAGS/keep9999"
check "other holder: no release"   test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 1"
run keep9999 off

# 7c. PostToolUse re-arm: repeat `on` while already holding is a no-op...
run tool1111 on
: > "$TMP/sudo.calls"
run tool1111 on
check "repeat on: no pmset"        test ! -s "$TMP/sudo.calls"
check "repeat on: still holding"   test -f "$FLAGS/tool1111"
# ...but after a Notification released the hold, the next tool call re-arms it
run tool1111 off
check "notification released"      test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 0"
run tool1111 on
check "post-tool re-arms hold"     test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 1"
run tool1111 off

# 8. Cursor-style JSON (conversation_id) is accepted as the session id
printf '{"conversation_id":"curs9876-abcd"}' | bash "$SCRIPT" on
check "cursor conversation_id"     test -f "$FLAGS/curs9876"
printf '{"conversation_id":"curs9876-abcd"}' | bash "$SCRIPT" off

# 8b. reap: terminal killed (no hooks fire, claude process gone) -> released
run kill1111 on
: > "$TMP/sudo.calls"
FAKE_CLAUDE=none bash "$SCRIPT" reap < /dev/null
check "reap drops orphan flag"     test ! -f "$FLAGS/kill1111"
check "reap re-enables sleep"      test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 0"

# ...but a live claude process keeps its hold
run live2222 on
: > "$TMP/sudo.calls"
bash "$SCRIPT" reap < /dev/null
check "reap spares live session"   test -f "$FLAGS/live2222"
check "reap: no pmset when held"   test ! -s "$TMP/sudo.calls"
run live2222 off

# ...and reap is a no-op once sleep is already back on (no log/pmset churn)
: > "$TMP/sudo.calls"
FAKE_SLEEPDISABLED=0 bash "$SCRIPT" reap < /dev/null
check "reap idle: no pmset"        test ! -s "$TMP/sudo.calls"

# 8c. a hook event with no transcript_path must not blind the staleness prune
printf '{"session_id":"keeptp1","transcript_path":"%s/tr-keep.jsonl"}' "$TMP" | bash "$SCRIPT" on
run keeptp1 on   # same session, JSON without transcript_path
check "transcript path preserved"  test "$(head -n1 "$FLAGS/keeptp1")" = "$TMP/tr-keep.jsonl"
run keeptp1 off

# 9. clear -> everything reset
run eeee7777 on
bash "$SCRIPT" clear < /dev/null
check "clear empties flags"        test -z "$(ls "$FLAGS")"
check "clear re-enables sleep"     test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 0"

exit $fail
