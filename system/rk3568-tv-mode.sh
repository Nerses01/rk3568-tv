#!/bin/sh
# Chooses what the board shows from boot: the TV app or the GNOME desktop (step 1.2; docs/02-board.md, "TV app or
# desktop"). Installed as /usr/local/sbin/rk3568-tv-mode; run as root, over SSH or adb.
#
# usage: rk3568-tv-mode tv        the TV app, now and at every boot
#        rk3568-tv-mode desktop   GNOME, now and at every boot (the TV app installed, but off)
#        rk3568-tv-mode status    which one the board boots into, and what runs now
#
# tv: the vendor's hdmi_hotplug.service is masked, since it starts GNOME on every HDMI hotplug; the board boots into
# multi-user.target (no desktop), where rk3568-tv.service starts. desktop undoes all of it. For the desktop just
# once, until the next boot: systemctl start gdm (and systemctl start rk3568-tv to go back).
set -u

app=rk3568-tv.service
hotplug=hdmi_hotplug.service
screen=${RK3568_TV_SCREEN:-/usr/local/lib/rk3568-tv/rk3568-tv-screen}

die() {
    echo "rk3568-tv-mode: $*" >&2
    exit 1
}

case ${1:-} in
tv)
    systemctl cat "$app" > /dev/null 2>&1 || die "$app is not installed (system/install.sh)"
    systemctl mask "$hotplug" > /dev/null 2>&1 || die "cannot mask $hotplug"
    systemctl set-default multi-user.target > /dev/null 2>&1 || die "cannot set the default target"
    systemctl enable "$app" > /dev/null 2>&1 || die "cannot enable $app"
    systemctl start "$app" || die "$app did not start: journalctl -u $app; its own lines: journalctl -t rk3568-tv"
    echo "rk3568-tv-mode: the TV app, now and at every boot"
    ;;
desktop)
    systemctl disable "$app" > /dev/null 2>&1
    systemctl stop "$app" 2> /dev/null
    [ -x "$screen" ] && "$screen" release
    systemctl unmask "$hotplug" > /dev/null 2>&1
    systemctl set-default graphical.target > /dev/null 2>&1 || die "cannot set the default target"
    systemctl start gdm || die "the desktop did not start: journalctl -u gdm"
    echo "rk3568-tv-mode: the desktop, now and at every boot"
    ;;
status)
    if [ "$(systemctl get-default)" = multi-user.target ] && systemctl is-enabled --quiet "$app" 2> /dev/null; then
        echo "boots into: the TV app"
    else
        echo "boots into: the desktop"
    fi
    echo "TV app: $(systemctl is-active "$app" 2> /dev/null)"
    echo "desktop: $(systemctl is-active gdm 2> /dev/null)"
    ;;
*)
    echo "usage: rk3568-tv-mode tv|desktop|status" >&2
    exit 2
    ;;
esac
