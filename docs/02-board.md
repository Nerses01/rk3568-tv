# The board

Facts gathered over SSH on 2026-11-11. This repository is public, so the board's IP, MAC and Bluetooth
addresses are left out on purpose; they are in the git-ignored `CLAUDE.local.md`.

## Hardware and software

| | |
|---|---|
| Board | GZPEITE RK3568 P01 (`/proc/device-tree/model`) |
| SoC | Rockchip RK3568: 4× Cortex-A55, Mali-G52 GPU, hardware decoding of H.264, H.265 and VP9 up to 4K |
| RAM | 4 GB |
| Storage | 16 GB eMMC (`mmcblk2`), partitions below |
| OS | Ubuntu 22.04.5 LTS, the vendor's image; the only user is `root`, `/home` is empty |
| Kernel | 5.10.209, Rockchip BSP |
| Desktop | GNOME, with Wayland and Xorg sessions installed |
| GPU driver | `libmali-bifrost-g52-g13p0-x11-gbm` 1.9, proprietary, for X11 and GBM |
| Video | `librockchip-mpp1` 1.5.0; GStreamer `rockchipmpp` plugin with `mppvideodec`, `mpph264enc`, `mpph265enc`, `mppjpegdec`, `mppjpegenc`; `librga2` 2.2.0 |
| mpv | 0.32 in `/usr/local/bin`; offers only `v4l2m2m-copy` hardware decoders |
| Held by apt | GStreamer base and GL packages, `libdrm` and others: the vendor's patched builds (`apt-mark showhold`) |
| Wi-Fi and Bluetooth | Realtek RTL8821CS. Wi-Fi over SDIO (module `RTL8821CS`); Bluetooth over UART `/dev/ttyS8` with the H5 protocol, attached by `rtk_hciattach`; firmware in `/lib/firmware/rtlbt` |
| Wi-Fi/Bluetooth start | `wifibt-init.service` runs `/usr/bin/wifibt-init.sh start` at boot |
| Audio | only the analog RK809 codec. The device tree's `hdmi-sound` node is `disabled`; `i2s@fe400000` is `okay` |
| HDMI-CEC | `/dev/cec0`; input device `hdmi_cec_key` |
| Other inputs | PWM IR receiver (input device `fe6e0030.pwm`), `adc-keys`, the power key |
| Toolchain | gcc and g++ 11.4, CMake, Ninja, git |

## eMMC partitions

| Partition | Label | Size | Mounted at | Notes |
|---|---|---|---|---|
| `mmcblk2p1` | `uboot` | 4 MB | | bootloader: never touch |
| `mmcblk2p2` | `misc` | 4 MB | | boot-mode flags (recovery) |
| `mmcblk2p3` | `boot` | 64 MB | | kernel and device tree; step 0.4 changes it |
| `mmcblk2p4` | `recovery` | 128 MB | | |
| `mmcblk2p5` | `backup` | 32 MB | | |
| `mmcblk2p6` | `gzpeite` | 16 MB | `/gzpeite` | vendor data |
| `mmcblk2p7` | `logo_rk` | 68 MB | `/mnt/logo` | boot logo |
| `mmcblk2p8` | `rootfs` | 6.5 GB | `/` | 93 % full on 2026-11-11; `/usr` alone is 4.9 GB |
| `mmcblk2p9` | `oem` | 128 MB | `/oem` | |
| `mmcblk2p10` | `userdata` | 7.6 GB | `/userdata` | room for builds and media |

## Access

- SSH as `root`, with the developer's key from the PC. sshd also accepts passwords (step 0.3 decides whether
  it should).
- TCP port 5555 (ADB) is open on the network. Step 0.3 closes it.

## Known faults and fixes

### Bluetooth won't turn on from the desktop

Symptom: the desktop's Bluetooth switch does nothing; `bluetoothd` logs `Failed to set mode: Failed (0x03)`;
`hciconfig hci0 up` says `Connection timed out`; `dmesg` shows `hci0: command 0x1003 tx timeout`.

Cause: Bluetooth was switched off in software (rfkill soft block, from the desktop's Bluetooth or airplane-mode
switch). That powers the chip down and it loses the firmware `rtk_hciattach` loaded at boot. Unblocking powers
it up again without firmware, and the `rtk_hciattach` still running from boot can't reach it.

Fix, as root (the same steps `wifibt-init.sh` takes at boot):

```sh
rfkill unblock bluetooth
hciconfig hci0 down 2>/dev/null; killall -q -9 rtk_hciattach
R=$(grep -rl '^bluetooth$' /sys/class/rfkill/*/type | sed 's/type$/state/')
echo 0 | tee $R >/dev/null; echo 0 > /proc/bluetooth/sleep/btwrite; sleep .5
echo 1 | tee $R >/dev/null; echo 1 > /proc/bluetooth/sleep/btwrite; sleep .5
systemd-run --unit=rtk-hciattach rtk_hciattach -n -s 115200 /dev/ttyS8 rtk_h5
sleep 5; hciconfig hci0 up; bluetoothctl power on
```

A reboot also fixes it: the saved rfkill state is "unblocked", so `wifibt-init.service` starts Bluetooth
normally. `wifibt-init.sh start_bt` does not help on a running system: it sees `hci0` and only tries to bring
it up.

### Bluetooth scan finds nothing, or discovery is "Busy"

`btmgmt find` answers `status 0x0a (Busy)` and `bluetoothctl devices` stays empty. Switching the adapter off
and on clears it:

```sh
bluetoothctl power off; sleep 2; bluetoothctl power on
```

### Pairing a Keychron keyboard

Set the keyboard's switch to Bluetooth and hold fn+1 (or 2, 3) for 4 seconds until the light blinks fast. In
pairing mode it advertises under a new address, so scan again after entering pairing mode and pair with the
address that shows up then. The `NoInputNoOutput` agent works; trust the device so that it reconnects by
itself.
