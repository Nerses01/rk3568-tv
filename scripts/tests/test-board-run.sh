#!/bin/sh
# Tests for scripts/board-run.sh. Stubs stand in for cmake, gcc, systemctl, systemd-run, journalctl and sleep, so
# they run anywhere with a POSIX shell (the PC's Git Bash, the board).
# usage: sh scripts/tests/test-board-run.sh   (exit status 0 when all tests pass)
set -u

here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../board-run.sh
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

src=$T/src
mkdir -p "$src/app" "$src/scripts" "$T/bin"
echo 'int main(void) { return 0; }' > "$src/scripts/board-keys.c"

# Each stub writes its name and arguments to calls. cmake configures by creating build.ninja; a build prints a
# compiler message with the board's path and fails with CMAKE_STATUS. systemctl is-active fails with
# ACTIVE_STATUS. gcc creates its output.
stub() {   # NAME BODY
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n%s\n' "$1" "$T" "$2" > "$T/bin/$1"
    chmod +x "$T/bin/$1"
}
stub cmake 'case "$1" in
-S) touch "$4/build.ninja" ;;
--build) echo "$(dirname "$2")/app/src/main.cpp:3:1: error: expected ;"; exit ${CMAKE_STATUS:-0} ;;
esac'
stub gcc 'while [ $# -gt 0 ]; do [ "$1" = -o ] && echo "#!/bin/sh" > "$2" && chmod +x "$2"; shift; done'   # Git Bash: executable means #!
stub systemctl 'case "$1" in is-active) exit ${ACTIVE_STATUS:-0} ;; esac'
stub systemd-run ''
stub journalctl 'echo "qrc:/Rk3568Tv/qml/Main.qml:5: something went wrong"'
stub sleep ''
# HDMI in sysfs and debugfs, played by files and a tee that acts like the kernel: "detect" on status leaves the
# cable's state (CABLE, default connected) in it, "on" forces it connected, "reset" clears the EDID override.
mkdir -p "$T/hdmi" "$T/debug"
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
export PATH RK3568_TV_SRC=$src RK3568_TV_HDMI=$T/hdmi RK3568_TV_HDMI_DEBUG=$T/debug
unset RK3568_TV_MODE CMAKE_STATUS ACTIVE_STATUS CABLE

run() {   # board-run.sh's exit status to $T/status, its output to $T/out, the stubs' calls to $T/calls
    rm -f "$T/calls"
    sh "$tool" > "$T/out" 2>&1
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }

run
check "first run: configures the build" has "$T/calls" "cmake -S $src/app -B $src/build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo"
check "first run: builds" has "$T/calls" "cmake --build $src/build"
check "first run: builds the keys tool" has "$T/calls" "gcc -O2 -Wall -Wextra -o $src/build/board-keys $src/scripts/board-keys.c"
check "stops the running app first" has "$T/calls" "systemctl stop rk3568-tv-dev"
check "starts the app as rk3568-tv-dev" has "$T/calls" "--unit=rk3568-tv-dev"
check "the app takes the screen from the desktop" has "$T/calls" "--property=Conflicts=gdm.service --property=After=gdm.service"
check "the app runs on EGLFS" has "$T/calls" "--setenv=QT_QPA_PLATFORM=eglfs --setenv=QT_QPA_EGLFS_INTEGRATION=eglfs_kms"
check "with the screen mode from kms.json" has "$T/calls" "--setenv=QT_QPA_EGLFS_KMS_CONFIG=$src/build/kms.json $src/build/rk3568-tv"
check "kms.json: 1080p60 by default" has "$src/build/kms.json" '"mode": "1920x1080@60"'
check "checks that the app keeps running" has "$T/calls" "systemctl is-active --quiet rk3568-tv-dev"
check "the vendor's HDMI hotplug service is masked until reboot" has "$T/calls" "systemctl mask --runtime --now hdmi_hotplug.service"
check "masked before HDMI is touched" before "$T/calls" "systemctl mask --runtime" "tee $T/hdmi/status detect"
check "the old app stops before HDMI is touched" before "$T/calls" "systemctl stop rk3568-tv-dev" "tee $T/hdmi/status detect"
check "says it runs" has "$T/out" "rk3568-tv is running at 1920x1080@60"
check "exit 0" status 0
check "build messages relative to the repository" has "$T/out" "app/src/main.cpp:3:1: error"
check "build messages without the board's folder" hasnt "$T/out" "$src/app"

run
check "second run: no new configure" hasnt "$T/calls" "cmake -S"
check "second run: the keys tool is up to date" hasnt "$T/calls" gcc

RK3568_TV_MODE=1280x720@50 run
check "RK3568_TV_MODE sets the mode" has "$src/build/kms.json" '"mode": "1280x720@50"'
unset RK3568_TV_MODE

CMAKE_STATUS=1 run
check "a failed build: exit 1" status 1
check "a failed build: says so" has "$T/out" "the build failed"
check "a failed build: shows the compiler's message" has "$T/out" "app/src/main.cpp:3:1: error"
check "a failed build: the running app is left alone" hasnt "$T/calls" "systemctl stop"
check "a failed build: nothing started" hasnt "$T/calls" systemd-run

ACTIVE_STATUS=3 run
check "an app that stops: exit 1" status 1
check "an app that stops: its log is shown" has "$T/out" "qrc:/Rk3568Tv/qml/Main.qml:5: something went wrong"

rm -f "$src/screen.edid"
run
check "screen: undoes an earlier stand-in" has "$T/calls" "tee $T/debug/edid_override reset"
check "screen: looks at the cable" has "$T/calls" "tee $T/hdmi/status detect"
check "screen connected: its EDID is saved" has "$src/screen.edid" TV-EDID
check "screen connected: HDMI is not forced" hasnt "$T/calls" "tee $T/hdmi/status on"
echo NEW-EDID > "$T/hdmi/edid"
run
check "screen connected: a new screen's EDID replaces the saved one" has "$src/screen.edid" NEW-EDID

CABLE=disconnected run
check "no screen: the saved EDID stands in" has "$T/debug/edid_override" NEW-EDID
check "no screen: HDMI forced on" has "$T/calls" "tee $T/hdmi/status on"
check "no screen: says so" has "$T/out" "no screen on HDMI; the app runs as if the last one were there"
check "no screen: the app starts" has "$T/calls" "systemd-run"
check "no screen: exit 0" status 0
check "no screen: the saved EDID is kept" has "$src/screen.edid" NEW-EDID

rm -f "$src/screen.edid"
CABLE=disconnected run
check "no screen, no saved EDID: exit 1" status 1
check "no screen, no saved EDID: says what to do" has "$T/out" "switch the screen on and deploy again"
check "no screen, no saved EDID: nothing started" hasnt "$T/calls" systemd-run

rm -f "$T/calls"
sh "$tool" stop > "$T/out" 2>&1
echo $? > "$T/status"
check "stop: exit 0" status 0
check "stop: stops the app" has "$T/calls" "systemctl stop rk3568-tv-dev"
check "stop: HDMI back to the real screen" before "$T/calls" "tee $T/debug/edid_override reset" "tee $T/hdmi/status detect"
check "stop: the hotplug service unmasked after that" before "$T/calls" "tee $T/hdmi/status detect" "systemctl unmask --runtime hdmi_hotplug.service"
check "stop: then the desktop" before "$T/calls" "systemctl unmask --runtime" "systemctl start gdm"
check "stop: builds nothing" hasnt "$T/calls" cmake
check "stop: says so" has "$T/out" "the desktop is back"
sh "$tool" restart > "$T/out" 2>&1
echo $? > "$T/status"
check "an unknown argument: exit 1" status 1

echo "$failures failed"
[ "$failures" -eq 0 ]
