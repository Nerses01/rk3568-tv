#!/bin/sh
# Tests for scripts/board-keys.c, in its dry run (no /dev/uinput needed). They compile it, so they need gcc and the
# Linux kernel headers: run them on the board.
# usage: sh scripts/tests/test-board-keys.sh   (exit status 0 when all tests pass)
set -u

here=$(cd "$(dirname "$0")" && pwd)
command -v gcc > /dev/null || { echo "SKIP: gcc not installed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
failures=0

check() {   # DESCRIPTION COMMAND...
    desc=$1
    shift
    if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; failures=$((failures + 1)); fi
}

gcc -O2 -Wall -Wextra -Werror -o "$T/board-keys" "$here/../board-keys.c" || { echo "FAIL it compiles"; exit 1; }
echo "ok   it compiles without warnings"

keys() {   # ARGS...: output to $T/out, exit status to $T/status
    BOARD_KEYS_DRY_RUN=1 "$T/board-keys" "$@" > "$T/out" 2> "$T/err"
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }
output() { [ "$(cat "$T/out")" = "$1" ]; }

keys right down:300 wait:500 enter
check "keys, a hold time and a pause" output "key right 40
key down 300
wait 500
key enter 40"
check "exit 0" status 0

keys up down left right enter back home menu esc space playpause volumeup volumedown
check "every key it knows" status 0

keys right jump
check "an unknown key: exit 2" status 2
check "an unknown key: nothing pressed" output ""
check "an unknown key: named" grep -q "not a key: 'jump'" "$T/err"

for bad in wait wait: wait:0 wait:x right: right:-5 right:60001 :40 verylongkeynamexyz; do
    keys "$bad"
    check "refuses '$bad'" status 2
done

keys
check "no key: exit 2" status 2

echo "$failures failed"
[ "$failures" -eq 0 ]
