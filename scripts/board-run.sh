#!/bin/sh
# Runs on the board, called by `scripts/board.sh deploy` (step 0.7). Builds the app from the sources that board.sh
# copied, then (re)starts it on the screen as the transient systemd unit rk3568-tv-dev. The unit conflicts with
# gdm, so the desktop stops while the app runs; `board.sh stop` brings it back. Its log is in the journal
# (journalctl -u rk3568-tv-dev). Build messages name files relative to the repository, so that VS Code can open
# them.
#
# A screen that is switched off reads as "disconnected" on HDMI, and the app would find no screen. The app is
# then run as if the last screen were there: HDMI is forced on with that screen's EDID, which is saved each time
# a screen is connected. The display keeps running, screenshots work, and a screen switched on shows the app.
# Each run undoes the forcing first and looks at the cable again; so does a reboot.
#
# The vendor's hdmi_hotplug.service would undo all this: udev restarts it on every HDMI hotplug event, and it
# requires the display manager, so it starts GNOME, which stops the app (docs/02-board.md). It is masked while the
# app runs, in /run only, so a reboot unmasks it too.
#
# usage: board-run.sh          build, then (re)start the app
#        board-run.sh stop     stop the app, return HDMI to the real screen, start the desktop
# Environment: RK3568_TV_SRC   the sources (default /userdata/dev/rk3568-tv)
#              RK3568_TV_MODE  the screen mode (default 1920x1080@60: a screen's preferred mode can be worse,
#                              see docs/04-ui-spike.md)
set -u

src=${RK3568_TV_SRC:-/userdata/dev/rk3568-tv}
mode=${RK3568_TV_MODE:-1920x1080@60}
hdmi=${RK3568_TV_HDMI:-/sys/class/drm/card0-HDMI-A-1}
hdmi_debug=${RK3568_TV_HDMI_DEBUG:-/sys/kernel/debug/dri/0/HDMI-A-1}
build=$src/build
edid=$src/screen.edid
unit=rk3568-tv-dev
hotplug=hdmi_hotplug.service
log=$build/build.log

die() {
    echo "board-run: $*" >&2
    exit 1
}

relative() { sed "s|$src/||g" "$log"; }

put() { printf '%s' "$1" | tee "$2" > /dev/null; }   # VALUE FILE: one write, no newline ("reset" must be 5 bytes)

screen() {
    put reset "$hdmi_debug/edid_override" && put detect "$hdmi/status" || die "cannot look at HDMI"
    if [ "$(cat "$hdmi/status")" = connected ]; then
        cat "$hdmi/edid" > "$edid.new" 2> /dev/null && [ -s "$edid.new" ] && mv "$edid.new" "$edid"
        rm -f "$edid.new"
        return
    fi
    [ -s "$edid" ] || die "no screen on HDMI (switched off?) and no saved EDID to stand in for one: switch the screen on and deploy again"
    tee "$hdmi_debug/edid_override" < "$edid" > /dev/null && put on "$hdmi/status" || die "cannot force HDMI on"
    echo "board-run: no screen on HDMI; the app runs as if the last one were there"
}

stop_app() {
    systemctl stop "$unit" 2> /dev/null
    systemctl reset-failed "$unit" 2> /dev/null
}

case ${1:-} in
'') ;;
stop)
    stop_app
    put reset "$hdmi_debug/edid_override"
    put detect "$hdmi/status"
    systemctl unmask --runtime "$hotplug" > /dev/null 2>&1
    systemctl start gdm || die "the desktop did not start"
    echo "board-run: the app is stopped and the desktop is back"
    exit 0
    ;;
*) die "usage: board-run.sh [stop]" ;;
esac

mkdir -p "$build" || die "cannot create $build"
if [ ! -f "$build/build.ninja" ]; then
    cmake -S "$src/app" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo > "$log" 2>&1 || {
        relative
        die "cmake could not configure the build"
    }
fi
if ! cmake --build "$build" > "$log" 2>&1; then
    relative
    die "the build failed"
fi
relative

if [ ! -x "$build/board-keys" ] || [ "$src/scripts/board-keys.c" -nt "$build/board-keys" ]; then
    gcc -O2 -Wall -Wextra -o "$build/board-keys" "$src/scripts/board-keys.c" || die "board-keys did not build"
fi

printf '{ "device": "/dev/dri/card0", "hwcursor": false, "outputs": [ { "name": "HDMI1", "mode": "%s" } ] }\n' \
    "$mode" > "$build/kms.json"

stop_app
systemctl mask --runtime --now "$hotplug" > /dev/null 2>&1
screen
systemd-run --quiet --collect --unit="$unit" --description="rk3568-tv, development build" \
    --property=Conflicts=gdm.service --property=After=gdm.service \
    --setenv=QT_QPA_PLATFORM=eglfs --setenv=QT_QPA_EGLFS_INTEGRATION=eglfs_kms \
    --setenv=QT_QPA_EGLFS_KMS_CONFIG="$build/kms.json" \
    "$build/rk3568-tv" || die "systemd-run could not start the app"

sleep 2   # the first frame comes after about a second (docs/04-ui-spike.md)
if ! systemctl is-active --quiet "$unit"; then
    journalctl -u "$unit" -n 30 --no-pager -o cat
    die "the app stopped; its log is above"
fi
echo "board-run: rk3568-tv is running at $mode"
