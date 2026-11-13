#!/bin/sh
# Tests for system/rk3568-tv-screen.sh. HDMI in sysfs and debugfs is played by files and a stub tee that acts like
# the kernel, so they run anywhere with a POSIX shell.
# usage: sh system/tests/test-rk3568-tv-screen.sh   (exit status 0 when all tests pass)
set -u

here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../rk3568-tv-screen.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
failures=0

check() {   # DESCRIPTION COMMAND...
    desc=$1
    shift
    if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; failures=$((failures + 1)); fi
}
has() { grep -qF -- "$2" "$1"; }      # FILE TEXT
hasnt() { ! grep -qF -- "$2" "$1" 2> /dev/null; }
line() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }
before() {   # FILE A B: A first appears before B
    a=$(line "$1" "$2")
    b=$(line "$1" "$3")
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

# tee acts like the kernel: "detect" on status leaves the cable's state (CABLE, default connected) in it, "on"
# forces it connected, "reset" clears the EDID override
mkdir -p "$T/hdmi" "$T/debug" "$T/bin"
echo connected > "$T/hdmi/status"
echo TV-EDID > "$T/hdmi/edid"
: > "$T/debug/edid_override"
cat > "$T/bin/tee" << EOF
#!/bin/sh
v=\$(cat)
echo "tee \$1 \$v" >> "$T/calls"
case "\$1:\$v" in
*/status:detect) echo "\${CABLE:-connected}" > "\$1" ;;
*/status:on) echo connected > "\$1" ;;
*/edid_override:reset) : > "\$1" ;;
*) printf '%s\n' "\$v" > "\$1" ;;
esac
EOF
chmod +x "$T/bin/tee"
PATH=$T/bin:$PATH
export PATH RK3568_TV_HDMI=$T/hdmi RK3568_TV_HDMI_DEBUG=$T/debug RK3568_TV_STATE=$T/state
unset CABLE

run() {   # ARGS...: output to $T/out, exit status to $T/status, tee's writes to $T/calls
    rm -f "$T/calls"
    sh "$tool" "$@" > "$T/out" 2>&1
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }

run prepare
check "prepare: undoes an earlier stand-in first" before "$T/calls" "tee $T/debug/edid_override reset" "tee $T/hdmi/status detect"
check "screen connected: exit 0" status 0
check "screen connected: its EDID is saved" has "$T/state/screen.edid" TV-EDID
check "screen connected: HDMI is not forced" hasnt "$T/calls" "tee $T/hdmi/status on"
echo NEW-EDID > "$T/hdmi/edid"
run prepare
check "a new screen's EDID replaces the saved one" has "$T/state/screen.edid" NEW-EDID

CABLE=disconnected run prepare
check "no screen: exit 0" status 0
check "no screen: the saved EDID stands in" has "$T/debug/edid_override" NEW-EDID
check "no screen: then HDMI is forced on" before "$T/calls" "tee $T/debug/edid_override NEW-EDID" "tee $T/hdmi/status on"
check "no screen: says so" has "$T/out" "standing in for the last one"
check "no screen: the saved EDID is kept" has "$T/state/screen.edid" NEW-EDID

rm -f "$T/state/screen.edid"
CABLE=disconnected run prepare
check "no screen, no saved EDID: exit 1, so that systemd tries again" status 1
check "no screen, no saved EDID: says so" has "$T/out" "waiting for a screen"
check "no screen, no saved EDID: HDMI not forced" hasnt "$T/calls" "tee $T/hdmi/status on"

run release
check "release: clears the override" has "$T/calls" "tee $T/debug/edid_override reset"
check "release: lets the kernel look at the cable" has "$T/calls" "tee $T/hdmi/status detect"
check "release: exit 0" status 0

run
check "no command: exit 2" status 2
run start
check "unknown command: exit 2" status 2

echo "$failures failed"
[ "$failures" -eq 0 ]
