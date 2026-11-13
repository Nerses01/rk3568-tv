#!/bin/sh
# Tests for system/bt-recover.sh. Every command it calls is replaced by a stub that only records its arguments,
# and the rfkill tree and btwrite file are fakes in a temporary folder, so nothing on the machine changes.
# usage: sh system/tests/test-bt-recover.sh   (exit status 0 when all tests pass)
set -u

here=$(cd "$(dirname "$0")" && pwd)
script=${BT_RECOVER:-$here/../bt-recover.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

stub() {   # NAME EXIT_STATUS: a command that appends "NAME ARGS" to calls and exits with EXIT_STATUS
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\nexit %s\n' "$1" "$tmp" "$2" > "$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}

setup() {   # a soft-blocked chip (rfkill0), Wi-Fi (rfkill1) and hci0 (rfkill2); all commands succeed
    rm -rf "$tmp/sys" "$tmp/bin"
    mkdir -p "$tmp/sys/rfkill0" "$tmp/sys/rfkill1" "$tmp/sys/rfkill2" "$tmp/bin"
    echo bluetooth > "$tmp/sys/rfkill0/type"; echo 0 > "$tmp/sys/rfkill0/state"
    echo wlan > "$tmp/sys/rfkill1/type"; echo untouched > "$tmp/sys/rfkill1/state"
    echo bluetooth > "$tmp/sys/rfkill2/type"; echo 1 > "$tmp/sys/rfkill2/state"
    echo 1 > "$tmp/btwrite"
    : > "$tmp/calls"
    for c in rfkill hciconfig killall systemctl systemd-run bluetoothctl; do stub "$c" 0; done
    # sleep records the power state at that moment, so the off-then-on order can be checked
    printf '#!/bin/sh\necho "sleep $* chip=$(cat %s/sys/rfkill0/state) hci0=$(cat %s/sys/rfkill2/state) btwrite=$(cat %s/btwrite)" >> "%s/calls"\n' \
        "$tmp" "$tmp" "$tmp" "$tmp" > "$tmp/bin/sleep"
    chmod +x "$tmp/bin/sleep"
}

run() {
    PATH="$tmp/bin:$PATH" RFKILL_DIR="$tmp/sys" BTWRITE="$tmp/btwrite" BT_UART=/dev/ttyS8 WAIT_HCI=3 \
        sh "$script" > "$tmp/out" 2> "$tmp/err"
    echo $? > "$tmp/status"
}

check() {   # DESCRIPTION COMMAND...
    desc=$1; shift
    if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; failures=$((failures + 1)); fi
}

status_is() { [ "$(cat "$tmp/status")" = "$1" ]; }
file_is() { [ "$(cat "$1")" = "$2" ]; }
err_has() { grep -q "$1" "$tmp/err"; }

# 1. The normal recovery: unblock, stop the old rtk_hciattach, power off then on, start rtk_hciattach, bring
#    hci0 up, power on in BlueZ; Wi-Fi's rfkill switch is never touched.
setup
run
cat > "$tmp/expected" <<EOF
rfkill unblock bluetooth
hciconfig hci0 down
killall -q -9 rtk_hciattach
systemctl stop rtk-hciattach
systemctl reset-failed rtk-hciattach
sleep 0.5 chip=0 hci0=0 btwrite=0
sleep 0.5 chip=1 hci0=1 btwrite=1
systemd-run -q --unit=rtk-hciattach rtk_hciattach -n -s 115200 /dev/ttyS8 rtk_h5
hciconfig hci0 up
bluetoothctl power on
EOF
check "recovery exits 0" status_is 0
check "recovery runs the boot-time steps in order" cmp -s "$tmp/expected" "$tmp/calls"
check "the chip's switch ends on" file_is "$tmp/sys/rfkill0/state" 1
check "hci0's switch ends on" file_is "$tmp/sys/rfkill2/state" 1
check "btwrite ends on" file_is "$tmp/btwrite" 1
check "Wi-Fi's rfkill switch is untouched" file_is "$tmp/sys/rfkill1/state" untouched
[ "$failures" = 0 ] || { echo "--- calls were:"; cat "$tmp/calls"; }

# 2. hci0's switch disappears while the chip is off: the script carries on with the chip's own switch.
setup
rm -r "$tmp/sys/rfkill2"
run
check "works without hci0's switch" status_is 0
check "chip switch ends on without hci0's switch" file_is "$tmp/sys/rfkill0/state" 1

# 3. hci0 never comes up: exit 1 with a message, after WAIT_HCI tries plus the first one.
setup
stub hciconfig 1
run
check "hci0 timeout exits 1" status_is 1
check "hci0 timeout says so" err_has "did not come up within 3 s"
check "hci0 timeout tries 4 times" [ "$(grep -c '^hciconfig hci0 up' "$tmp/calls")" = 4 ]
check "no BlueZ power-on after a timeout" [ "$(grep -c '^bluetoothctl' "$tmp/calls")" = 0 ]

# 4. rtk_hciattach can't be started: exit 1 before waiting for hci0.
setup
stub systemd-run 1
run
check "failed start exits 1" status_is 1
check "failed start says so" err_has "could not start rtk_hciattach"
check "failed start doesn't wait for hci0" [ "$(grep -c '^hciconfig hci0 up' "$tmp/calls")" = 0 ]

# 5. No Bluetooth rfkill switch at all: exit 1 and change nothing.
setup
echo wlan > "$tmp/sys/rfkill0/type"
echo wlan > "$tmp/sys/rfkill2/type"
run
check "no switch exits 1" status_is 1
check "no switch says so" err_has "no Bluetooth rfkill switch"
check "no switch calls nothing" [ ! -s "$tmp/calls" ]

echo "$failures failure(s)"
[ "$failures" = 0 ]
