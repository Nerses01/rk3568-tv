#!/bin/sh
# Stands in for a switched-off screen, so that the TV app can start (step 1.2; docs/02-board.md, "A switched-off
# screen leaves no screen"). Installed as /usr/local/lib/rk3568-tv/rk3568-tv-screen; rk3568-tv.service runs
# `prepare` as root before the app.
#
# A screen that is switched off reads as "disconnected" on HDMI, and the app would find no screen. `prepare` first
# undoes any earlier stand-in and lets the kernel look at the cable. With a screen there, it saves the screen's EDID.
# Without one, it forces HDMI on with the saved EDID: the display runs as if the screen were there, and the screen
# shows the app as soon as it is switched on. Without a saved EDID it fails, and systemd tries again later.
#
# usage: rk3568-tv-screen prepare    before the app starts
#        rk3568-tv-screen release    undo the stand-in (when the desktop takes over)
# Environment (for the tests): RK3568_TV_HDMI, RK3568_TV_HDMI_DEBUG, RK3568_TV_STATE
set -u

hdmi=${RK3568_TV_HDMI:-/sys/class/drm/card0-HDMI-A-1}
hdmi_debug=${RK3568_TV_HDMI_DEBUG:-/sys/kernel/debug/dri/0/HDMI-A-1}
edid=${RK3568_TV_STATE:-/var/lib/rk3568-tv}/screen.edid

die() {
    echo "rk3568-tv-screen: $*" >&2
    exit 1
}

put() { printf '%s' "$1" | tee "$2" > /dev/null; }   # VALUE FILE: one write, no newline ("reset" must be 5 bytes)

release() {
    put reset "$hdmi_debug/edid_override" && put detect "$hdmi/status" || die "cannot look at HDMI"
}

case ${1:-} in
prepare)
    release
    if [ "$(cat "$hdmi/status")" = connected ]; then
        mkdir -p "$(dirname "$edid")"
        cat "$hdmi/edid" > "$edid.new" 2> /dev/null && [ -s "$edid.new" ] && mv "$edid.new" "$edid"
        rm -f "$edid.new"
        exit 0
    fi
    [ -s "$edid" ] || die "no screen on HDMI, and no saved EDID to stand in for one: waiting for a screen"
    tee "$hdmi_debug/edid_override" < "$edid" > /dev/null && put on "$hdmi/status" || die "cannot force HDMI on"
    echo "rk3568-tv-screen: no screen on HDMI; standing in for the last one"
    ;;
release) release ;;
*)
    echo "usage: rk3568-tv-screen prepare|release" >&2
    exit 2
    ;;
esac
