#!/bin/sh
# Tests for system/install.sh. A temporary folder stands in for / (RK3568_TV_ROOT), and stubs stand in for id,
# useradd, usermod, chown and systemctl, so they run anywhere with a POSIX shell.
# usage: sh system/tests/test-install.sh   (exit status 0 when all tests pass)
set -u

here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../install.sh
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
absent() { [ ! -e "$1" ]; }
executable() { [ -x "$1" ]; }

mkdir -p "$T/bin"
stub() {   # NAME BODY: records "NAME ARGS" to calls
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n%s\n' "$1" "$T" "$2" > "$T/bin/$1"
    chmod +x "$T/bin/$1"
}
stub id '[ -n "${HAVE_USER:-}" ]'
stub useradd ''
stub usermod ''
stub chown ''
stub systemctl ''
printf '#!/bin/sh\necho "screen $*" >> "%s/calls"\n' "$T" > "$T/screen"   # never the board's real HDMI
chmod +x "$T/screen"
PATH=$T/bin:$PATH
r=$T/root
export PATH RK3568_TV_ROOT=$r RK3568_TV_SCREEN=$T/screen
unset HAVE_USER
printf '#!/bin/sh\necho app\n' > "$T/rk3568-tv"

run() {   # ARGS...: output to $T/out, exit status to $T/status, the calls to $T/calls
    rm -f "$T/calls"
    sh "$tool" "$@" > "$T/out" 2>&1
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }

run "$T/rk3568-tv"
check "install: exit 0" status 0
check "a new user tv: a system user, its own group, no login" has "$T/calls" "useradd --system --user-group --home-dir /var/lib/rk3568-tv --shell /usr/sbin/nologin"
check "tv's groups: screen, GPU, video decoder, input, sound" has "$T/calls" "usermod --append --groups video,render,input,audio tv"
check "tv's home" has "$T/calls" "chown tv:tv $r/var/lib/rk3568-tv"
check "the app" executable "$r/usr/local/bin/rk3568-tv"
check "the unit" has "$r/etc/systemd/system/rk3568-tv.service" "ExecStart=/usr/local/bin/rk3568-tv"
check "the screen tool, where the unit expects it" executable "$r/usr/local/lib/rk3568-tv/rk3568-tv-screen"
check "the mode tool" executable "$r/usr/local/sbin/rk3568-tv-mode"
check "the screen mode: 1080p60, in tv's home" has "$r/var/lib/rk3568-tv/kms.json" '"mode": "1920x1080@60"'
check "the screen mode: tv may change it" has "$T/calls" "chown tv:tv $r/var/lib/rk3568-tv/kms.json"
check "polkit: tv may manage Wi-Fi" has "$r/etc/polkit-1/localauthority/50-local.d/rk3568-tv.pkla" "Identity=unix-user:tv"
check "systemd reads the unit" has "$T/calls" "systemctl daemon-reload"
check "the boot isn't changed" sh -c "! grep -qE 'systemctl (enable|set-default|start|mask)' '$T/calls'"

echo '{ "outputs": [ { "name": "HDMI1", "mode": "1280x720@50" } ] }' > "$r/var/lib/rk3568-tv/kms.json"
printf '#!/bin/sh\necho app 2\n' > "$T/rk3568-tv"
HAVE_USER=1 run "$T/rk3568-tv"
check "update: exit 0" status 0
check "update: the user exists, no new one" hasnt "$T/calls" useradd
check "update: the groups again" has "$T/calls" "usermod --append --groups video,render,input,audio tv"
check "update: the new app" has "$r/usr/local/bin/rk3568-tv" "app 2"
check "update: a chosen screen mode stays" has "$r/var/lib/rk3568-tv/kms.json" "1280x720@50"

rm "$r/var/lib/rk3568-tv/kms.json"
mkdir -p "$r/etc/rk3568-tv" && echo '{ "outputs": [ { "name": "HDMI1", "mode": "3840x2160@30" } ] }' > "$r/etc/rk3568-tv/kms.json"
HAVE_USER=1 run "$T/rk3568-tv"
check "update from before step 1.6: exit 0" status 0
check "update from before step 1.6: the screen mode moves to tv's home" has "$r/var/lib/rk3568-tv/kms.json" "3840x2160@30"
check "update from before step 1.6: nothing left in /etc" absent "$r/etc/rk3568-tv"

run "$T/none"
check "no binary: exit 1" status 1
check "no binary: says so" has "$T/out" "no app binary at $T/none"
run
check "no argument: exit 2" status 2

mkdir -p "$r/var/lib/rk3568-tv" && echo EDID > "$r/var/lib/rk3568-tv/screen.edid"
run --remove
check "remove: exit 0" status 0
check "remove: the desktop from boot first" has "$T/calls" "systemctl set-default graphical.target"
check "remove: the app" absent "$r/usr/local/bin/rk3568-tv"
check "remove: the unit" absent "$r/etc/systemd/system/rk3568-tv.service"
check "remove: the tools" absent "$r/usr/local/lib/rk3568-tv"
check "remove: the mode tool" absent "$r/usr/local/sbin/rk3568-tv-mode"
check "remove: the settings" absent "$r/etc/rk3568-tv"
check "remove: the polkit rule" absent "$r/etc/polkit-1/localauthority/50-local.d/rk3568-tv.pkla"
check "remove: tv's home stays" has "$r/var/lib/rk3568-tv/screen.edid" EDID

echo "$failures failed"
[ "$failures" -eq 0 ]
