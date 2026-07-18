#!/bin/bash
# Self-contained test for lid-awake.sh — no framework, no root.
# Stubs `sudo` via PATH (script calls `sudo -n /usr/bin/pmset ...`) and
# points HOME at a temp dir so flags/log are isolated.
set -u
SCRIPT="$(cd "$(dirname "$0")" && pwd)/lid-awake.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# fake sudo: record the pmset args instead of running them
mkdir -p "$TMP/bin"
cat > "$TMP/bin/sudo" <<EOF
#!/bin/bash
echo "\$*" >> "$TMP/sudo.calls"
EOF
chmod +x "$TMP/bin/sudo"
export PATH="$TMP/bin:$PATH" HOME="$TMP"
FLAGS="$TMP/.claude/scripts/.lid-awake-flags"

run(){ printf '{"session_id":"%s"}' "$1" | bash "$SCRIPT" "$2"; }
last_call(){ tail -n1 "$TMP/sudo.calls" 2>/dev/null; }

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

# 5. stale flag (>12h old) pruned on next event
touch "$FLAGS/deadsess"
touch -t "$(date -v-13H '+%Y%m%d%H%M' 2>/dev/null || date -d '13 hours ago' '+%Y%m%d%H%M')" "$FLAGS/deadsess"
run cccc3333 on
check "stale flag pruned"          test ! -f "$FLAGS/deadsess"

# 6. clear -> everything reset
run cccc3333 on
bash "$SCRIPT" clear < /dev/null
check "clear empties flags"        test -z "$(ls "$FLAGS")"
check "clear re-enables sleep"     test "$(last_call)" = "-n /usr/bin/pmset -a disablesleep 0"

exit $fail
