#!/bin/sh
# Runs on the board, called by `scripts/board.sh` (steps 0.7 and 1.2). Builds the app from the sources that board.sh
# copied, installs it with system/install.sh and restarts it: the same unit, user and settings as at boot
# (rk3568-tv.service). Its log is in the journal (journalctl -u rk3568-tv). Build messages name files relative to
# the repository, so that VS Code can open them.
#
# The vendor's hdmi_hotplug.service starts GNOME on every HDMI hotplug, which stops the app (docs/02-board.md). In
# TV mode (rk3568-tv-mode tv) it is masked for good; otherwise it is masked here while the app runs, in /run only, so
# a reboot unmasks it too.
#
# usage: board-run.sh          build the app, install it, restart it
#        board-run.sh test     build everything and run the tests (offscreen; the running app stays)
#        board-run.sh stop     stop the app and start the desktop, until the next boot or deploy
# Environment: RK3568_TV_SRC   the sources (default /userdata/dev/rk3568-tv)
set -u

src=${RK3568_TV_SRC:-/userdata/dev/rk3568-tv}
build=$src/build
app=rk3568-tv.service
hotplug=hdmi_hotplug.service
screen=${RK3568_TV_SCREEN:-/usr/local/lib/rk3568-tv/rk3568-tv-screen}
log=$build/build.log

die() {
    echo "board-run: $*" >&2
    exit 1
}

relative() { sed "s|$src/||g" "$log"; }

build() {   # [cmake --build ARGS...]: configure if needed, then build
    mkdir -p "$build" || die "cannot create $build"
    if [ ! -f "$build/build.ninja" ]; then
        cmake -S "$src/app" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo > "$log" 2>&1 || {
            relative
            die "cmake could not configure the build"
        }
    fi
    if ! cmake --build "$build" "$@" > "$log" 2>&1; then
        relative
        die "the build failed"
    fi
    relative
}

case ${1:-} in
'') ;;
test)
    # everything, tests included, then the tests; offscreen, so the running app stays
    build
    ctest --test-dir "$build" --output-on-failure > "$build/test.log" 2>&1
    status=$?
    sed "s|$src/||g" "$build/test.log"
    exit $status
    ;;
stop)
    systemctl stop "$app"
    [ -x "$screen" ] && "$screen" release
    systemctl unmask --runtime "$hotplug" > /dev/null 2>&1
    systemctl start gdm || die "the desktop did not start"
    echo "board-run: the app is stopped and the desktop is back, until the next boot or deploy"
    exit 0
    ;;
*) die "usage: board-run.sh [test|stop]" ;;
esac

build --target rk3568-tv   # the app alone: the tests wait for `board-run.sh test`

if [ ! -x "$build/board-keys" ] || [ "$src/scripts/board-keys.c" -nt "$build/board-keys" ]; then
    gcc -O2 -Wall -Wextra -o "$build/board-keys" "$src/scripts/board-keys.c" || die "board-keys did not build"
fi

sh "$src/system/install.sh" "$build/rk3568-tv" || die "the install failed"
systemctl mask --runtime --now "$hotplug" > /dev/null 2>&1
systemctl restart "$app" || die "$app did not start"

sleep 3   # the first frame comes after about a second (docs/04-ui-spike.md)
if ! systemctl is-active --quiet "$app"; then
    journalctl -u "$app" -n 30 --no-pager -o cat
    die "the app stopped; its log is above"
fi
echo "board-run: rk3568-tv is running"
