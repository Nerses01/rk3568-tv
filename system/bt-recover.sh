#!/bin/sh
# Bring Bluetooth back after it was switched off in software (rfkill soft block, for example from the desktop's
# Bluetooth or airplane-mode switch). Switching it off powers the RTL8821CS down, and it loses the firmware that
# rtk_hciattach loaded at boot. These are the steps /usr/bin/wifibt-init.sh takes at boot: power-cycle the chip,
# then start rtk_hciattach again so that it loads the firmware. See docs/02-board.md, "Known faults and fixes".
#
# usage: bt-recover.sh   (as root; exit status 0 when hci0 is up and powered on)
#
# The paths can be overridden for the tests (system/tests/test-bt-recover.sh).
set -u

rfkill_dir=${RFKILL_DIR:-/sys/class/rfkill}
btwrite=${BTWRITE:-/proc/bluetooth/sleep/btwrite}
uart=${BT_UART:-/dev/ttyS8}
wait_hci=${WAIT_HCI:-15}   # seconds to wait for hci0 after starting rtk_hciattach

fail() { echo "bt-recover: $*" >&2; exit 1; }

# The Bluetooth rfkill switches: the chip's own and, while it exists, hci0's.
states=
for t in "$rfkill_dir"/*/type; do
    [ -f "$t" ] && [ "$(cat "$t")" = bluetooth ] && states="$states ${t%type}state"
done
[ -n "$states" ] || fail "no Bluetooth rfkill switch in $rfkill_dir"

power() {   # 0 = off, 1 = on
    for s in $states; do
        [ -e "$s" ] && echo "$1" > "$s"
    done
    echo "$1" > "$btwrite" || fail "cannot write $btwrite"
    sleep 0.5
}

rfkill unblock bluetooth
hciconfig hci0 down 2>/dev/null
killall -q -9 rtk_hciattach
systemctl stop rtk-hciattach 2>/dev/null
systemctl reset-failed rtk-hciattach 2>/dev/null

power 0
power 1

systemd-run -q --unit=rtk-hciattach rtk_hciattach -n -s 115200 "$uart" rtk_h5 ||
    fail "could not start rtk_hciattach"

# hci0 appears once the firmware is loaded, a few seconds after rtk_hciattach starts.
i=0
until hciconfig hci0 up 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -le "$wait_hci" ] || fail "hci0 did not come up within $wait_hci s"
    sleep 1
done
bluetoothctl power on > /dev/null || fail "bluetoothctl power on failed"
echo "bt-recover: Bluetooth is back"
