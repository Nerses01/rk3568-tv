#!/bin/sh
# Tests for scripts/board-run.sh. Stubs stand in for cmake, ctest, gcc, systemctl, journalctl, sleep, install.sh and
# the screen tool, so they run anywhere with a POSIX shell (the PC's Git Bash, the board).
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
mkdir -p "$src/app" "$src/scripts" "$src/system" "$T/bin"
echo 'int main(void) { return 0; }' > "$src/scripts/board-keys.c"

# Each stub writes its name and arguments to calls. cmake configures by creating build.ninja; a build prints a
# compiler message with the board's path and fails with CMAKE_STATUS. ctest fails with CTEST_STATUS. systemctl
# is-active fails with ACTIVE_STATUS, start with GDM_STATUS. install.sh fails with INSTALL_STATUS. gcc creates its
# output.
stub() {   # NAME BODY
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n%s\n' "$1" "$T" "$2" > "$T/bin/$1"
    chmod +x "$T/bin/$1"
}
stub cmake 'case "$1" in
-S) touch "$4/build.ninja" ;;
--build) echo "$(dirname "$2")/app/src/main.cpp:3:1: error: expected ;"; exit ${CMAKE_STATUS:-0} ;;
esac'
stub ctest 'echo "$(dirname "$2")/app/tests/tst_x.cpp: FAIL!"; exit ${CTEST_STATUS:-0}'
stub gcc 'while [ $# -gt 0 ]; do [ "$1" = -o ] && echo "#!/bin/sh" > "$2" && chmod +x "$2"; shift; done'   # Git Bash: executable means #!
stub systemctl 'case "$1" in is-active) exit ${ACTIVE_STATUS:-0} ;; start) exit ${GDM_STATUS:-0} ;; esac'
stub journalctl 'echo "qrc:/qt/qml/Rk3568Tv/qml/Main.qml:5: something went wrong"'
stub sleep ''
printf '#!/bin/sh\necho "install.sh $*" >> "%s/calls"\nexit ${INSTALL_STATUS:-0}\n' "$T" > "$src/system/install.sh"
printf '#!/bin/sh\necho "screen $*" >> "%s/calls"\n' "$T" > "$T/screen"
chmod +x "$T/screen"
PATH=$T/bin:$PATH
export PATH RK3568_TV_SRC=$src RK3568_TV_SCREEN=$T/screen
unset CMAKE_STATUS CTEST_STATUS ACTIVE_STATUS GDM_STATUS INSTALL_STATUS

run() {   # ARGS...: board-run.sh's exit status to $T/status, its output to $T/out, the stubs' calls to $T/calls
    rm -f "$T/calls"
    sh "$tool" "$@" > "$T/out" 2>&1
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }

run
check "first run: configures the build" has "$T/calls" "cmake -S $src/app -B $src/build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo"
check "builds the app alone" has "$T/calls" "cmake --build $src/build --target rk3568-tv"
check "runs no tests" hasnt "$T/calls" ctest
check "first run: builds the keys tool" has "$T/calls" "gcc -O2 -Wall -Wextra -o $src/build/board-keys $src/scripts/board-keys.c"
check "installs the build" has "$T/calls" "install.sh $src/build/rk3568-tv"
check "masks the vendor's hotplug service until reboot" has "$T/calls" "systemctl mask --runtime --now hdmi_hotplug.service"
check "restarts the app's unit" has "$T/calls" "systemctl restart rk3568-tv.service"
check "installed, masked, then restarted" before "$T/calls" "install.sh" "systemctl mask --runtime"
check "masked before the app starts" before "$T/calls" "systemctl mask --runtime" "systemctl restart"
check "checks that the app keeps running" has "$T/calls" "systemctl is-active --quiet rk3568-tv.service"
check "says it runs" has "$T/out" "rk3568-tv is running"
check "exit 0" status 0
check "build messages relative to the repository" has "$T/out" "app/src/main.cpp:3:1: error"
check "build messages without the board's folder" hasnt "$T/out" "$src/app"

run
check "second run: no new configure" hasnt "$T/calls" "cmake -S"
check "second run: the keys tool is up to date" hasnt "$T/calls" gcc

CMAKE_STATUS=1 run
check "a failed build: exit 1" status 1
check "a failed build: says so" has "$T/out" "the build failed"
check "a failed build: shows the compiler's message" has "$T/out" "app/src/main.cpp:3:1: error"
check "a failed build: nothing installed" hasnt "$T/calls" install.sh
check "a failed build: the running app is left alone" hasnt "$T/calls" systemctl

INSTALL_STATUS=1 run
check "a failed install: exit 1" status 1
check "a failed install: nothing restarted" hasnt "$T/calls" "systemctl restart"

ACTIVE_STATUS=3 run
check "an app that stops: exit 1" status 1
check "an app that stops: its log is shown" has "$T/out" "qrc:/qt/qml/Rk3568Tv/qml/Main.qml:5: something went wrong"

run stop
check "stop: exit 0" status 0
check "stop: stops the app" has "$T/calls" "systemctl stop rk3568-tv.service"
check "stop: the screen stand-in ends" has "$T/calls" "screen release"
check "stop: the hotplug service unmasked after that" before "$T/calls" "screen release" "systemctl unmask --runtime hdmi_hotplug.service"
check "stop: then the desktop" before "$T/calls" "systemctl unmask --runtime" "systemctl start gdm"
check "stop: builds nothing" hasnt "$T/calls" cmake
check "stop: says so" has "$T/out" "the desktop is back"
GDM_STATUS=1 run stop
check "stop: a desktop that doesn't start fails it" status 1

run restart
check "an unknown argument: exit 1" status 1

run test
check "test: builds everything" grep -qx "cmake --build $src/build" "$T/calls"
check "test: runs the tests" has "$T/calls" "ctest --test-dir $src/build --output-on-failure"
check "test: exit 0" status 0
check "test: the running app stays" hasnt "$T/calls" systemctl
check "test: nothing installed" hasnt "$T/calls" install.sh
check "test: messages relative to the repository" has "$T/out" "app/tests/tst_x.cpp: FAIL!"
CTEST_STATUS=8 run test
check "test: failing tests fail it" status 8
CMAKE_STATUS=1 run test
check "test: a failed build fails it" status 1
check "test: and runs no tests" hasnt "$T/calls" ctest

echo "$failures failed"
[ "$failures" -eq 0 ]
