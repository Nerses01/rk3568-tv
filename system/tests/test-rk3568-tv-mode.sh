#!/bin/sh
# Tests for system/rk3568-tv-mode.sh, with a stub systemctl, so they run anywhere with a POSIX shell.
# usage: sh system/tests/test-rk3568-tv-mode.sh   (exit status 0 when all tests pass)
set -u

here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../rk3568-tv-mode.sh
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

# systemctl records its calls. `cat` fails when NOT_INSTALLED; get-default prints DEFAULT; is-enabled succeeds when
# ENABLED; is-active prints ACTIVE_APP or ACTIVE_GDM; start fails for START_FAILS. The screen tool records too.
mkdir -p "$T/bin"
cat > "$T/bin/systemctl" << EOF
#!/bin/sh
echo "systemctl \$*" >> "$T/calls"
case "\$1" in
cat) [ -z "\${NOT_INSTALLED:-}" ] ;;
get-default) echo "\${DEFAULT:-graphical.target}" ;;
is-enabled) [ -n "\${ENABLED:-}" ] ;;
is-active) case "\$2" in rk3568-tv.service) echo "\${ACTIVE_APP:-inactive}" ;; *) echo "\${ACTIVE_GDM:-active}" ;; esac ;;
start) [ "\$2" != "\${START_FAILS:-}" ] ;;
esac
EOF
printf '#!/bin/sh\necho "screen $*" >> "%s/calls"\n' "$T" > "$T/screen"
chmod +x "$T/bin/systemctl" "$T/screen"
PATH=$T/bin:$PATH
export PATH RK3568_TV_SCREEN=$T/screen
unset NOT_INSTALLED DEFAULT ENABLED ACTIVE_APP ACTIVE_GDM START_FAILS

run() {   # ARGS...: output to $T/out, exit status to $T/status, the calls to $T/calls
    rm -f "$T/calls"
    sh "$tool" "$@" > "$T/out" 2>&1
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }

run tv
check "tv: exit 0" status 0
check "tv: the vendor's hotplug service is masked for good" has "$T/calls" "systemctl mask hdmi_hotplug.service"
check "tv: no desktop from boot" has "$T/calls" "systemctl set-default multi-user.target"
check "tv: the app from boot" has "$T/calls" "systemctl enable rk3568-tv.service"
check "tv: and now" has "$T/calls" "systemctl start rk3568-tv.service"
check "tv: masked before anything starts" before "$T/calls" "systemctl mask hdmi_hotplug" "systemctl start rk3568-tv"
check "tv: says so" has "$T/out" "the TV app, now and at every boot"

NOT_INSTALLED=1 run tv
check "tv without the app installed: exit 1" status 1
check "tv without the app installed: says so" has "$T/out" "not installed"
check "tv without the app installed: nothing changed" hasnt "$T/calls" "set-default"

START_FAILS=rk3568-tv.service run tv
check "tv, the app doesn't start: exit 1" status 1
check "tv, the app doesn't start: points to its log" has "$T/out" "journalctl -t rk3568-tv"

run desktop
check "desktop: exit 0" status 0
check "desktop: the app no longer from boot" has "$T/calls" "systemctl disable rk3568-tv.service"
check "desktop: the app stops" has "$T/calls" "systemctl stop rk3568-tv.service"
check "desktop: the screen stand-in ends" has "$T/calls" "screen release"
check "desktop: the hotplug service is back" has "$T/calls" "systemctl unmask hdmi_hotplug.service"
check "desktop: the desktop from boot" has "$T/calls" "systemctl set-default graphical.target"
check "desktop: and now" has "$T/calls" "systemctl start gdm"
check "desktop: the app stops before the desktop starts" before "$T/calls" "systemctl stop rk3568-tv" "systemctl start gdm"
START_FAILS=gdm run desktop
check "desktop that doesn't start: exit 1" status 1

DEFAULT=multi-user.target ENABLED=1 ACTIVE_APP=active ACTIVE_GDM=inactive run status
check "status in TV mode" has "$T/out" "boots into: the TV app"
check "status: what runs" has "$T/out" "TV app: active"
run status
check "status in desktop mode" has "$T/out" "boots into: the desktop"
DEFAULT=multi-user.target run status
check "status: multi-user without the app is the desktop's way" has "$T/out" "boots into: the desktop"
check "status: changes nothing" sh -c "! grep -qE 'systemctl (mask|unmask|enable|disable|set-default|start|stop) ' '$T/calls'"

run
check "no command: exit 2" status 2
run reboot
check "unknown command: exit 2" status 2

echo "$failures failed"
[ "$failures" -eq 0 ]
