#!/bin/sh
# Installs or updates the TV app on the board (step 1.2): the user tv, the app, its systemd unit and scripts, and a
# default screen mode. Run as root, from this folder's copy on the board; `scripts/board.sh deploy` does that after
# each build. It doesn't change what the board boots into: that's `rk3568-tv-mode tv` (rk3568-tv-mode.sh).
# The .deb of step 1.8 will do the same.
#
# usage: install.sh APP_BINARY    install or update
#        install.sh --remove      the desktop back from boot, then remove the app, its unit, scripts and settings
#                                 (the user tv and its home /var/lib/rk3568-tv stay)
# Environment (for the tests): RK3568_TV_ROOT, a folder that stands in for /
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=${RK3568_TV_ROOT:-}
home=/var/lib/rk3568-tv
polkit=/etc/polkit-1/localauthority/50-local.d/rk3568-tv.pkla

die() {
    echo "install: $*" >&2
    exit 1
}

case ${1:-} in
--remove)
    [ -x "$root/usr/local/sbin/rk3568-tv-mode" ] && "$root/usr/local/sbin/rk3568-tv-mode" desktop
    systemctl disable rk3568-tv.service > /dev/null 2>&1
    rm -f "$root/usr/local/bin/rk3568-tv" "$root/etc/systemd/system/rk3568-tv.service" \
        "$root/usr/local/sbin/rk3568-tv-mode" "$root$polkit"
    rm -rf "$root/usr/local/lib/rk3568-tv" "$root/etc/rk3568-tv"
    systemctl daemon-reload
    echo "install: removed; the user tv and $home stay"
    exit 0
    ;;
'' | -*)
    echo "usage: install.sh APP_BINARY | --remove" >&2
    exit 2
    ;;
esac
binary=$1
[ -f "$binary" ] || die "no app binary at $binary"

# The user: no login, no password; its groups open the screen, the GPU, the video decoder (video, render), the
# keyboards and remotes (input) and the sound (audio)
if ! id tv > /dev/null 2>&1; then
    useradd --system --user-group --home-dir "$home" --shell /usr/sbin/nologin --comment "rk3568-tv app" tv ||
        die "cannot create the user tv"
fi
usermod --append --groups video,render,input,audio tv || die "cannot add tv to its groups"
mkdir -p "$root$home" && chown tv:tv "$root$home" || die "cannot create $home"

install -D -m 0755 "$binary" "$root/usr/local/bin/rk3568-tv" &&
    install -D -m 0644 "$here/rk3568-tv.service" "$root/etc/systemd/system/rk3568-tv.service" &&
    install -D -m 0755 "$here/rk3568-tv-screen.sh" "$root/usr/local/lib/rk3568-tv/rk3568-tv-screen" &&
    install -D -m 0755 "$here/rk3568-tv-mode.sh" "$root/usr/local/sbin/rk3568-tv-mode" &&
    install -D -m 0644 "$here/rk3568-tv.pkla" "$root$polkit" || die "cannot install the files"

# The screen mode, which the app changes (Settings, Display), in tv's home: 1080p at 60 Hz unless chosen otherwise
# (a screen's preferred mode can be worse: docs/04-ui-spike.md). An older install's in /etc moves there.
kms=$root$home/kms.json
if [ ! -f "$kms" ]; then
    if [ -f "$root/etc/rk3568-tv/kms.json" ]; then
        mv "$root/etc/rk3568-tv/kms.json" "$kms" && { rmdir "$root/etc/rk3568-tv" 2> /dev/null || true; }
    else
        printf '%s\n' '{ "device": "/dev/dri/card0", "hwcursor": false, "outputs": [ { "name": "HDMI1", "mode": "1920x1080@60" } ] }' \
            > "$kms"
    fi && chown tv:tv "$kms" || die "cannot write the screen mode"
fi

systemctl daemon-reload || die "systemctl daemon-reload failed"
echo "install: rk3568-tv installed (rk3568-tv-mode status: what the board boots into)"
