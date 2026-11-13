# The board

Facts gathered over SSH and at the board from 2026-11-11 to 2026-11-13. This repository is public, so the board's
IP, MAC and Bluetooth addresses are left out on purpose; they are in the git-ignored `CLAUDE.local.md`.

## Hardware and software

| | |
|---|---|
| Board | GZPEITE RK3568 P01 (`/proc/device-tree/model`); appears to be GZPEITE's build of RYD's 8897 mainboard ("Vendor files" below) |
| SoC | Rockchip RK3568: 4× Cortex-A55, Mali-G52 GPU, hardware decoding of H.264, H.265 and VP9 up to 4K |
| RAM | 4 GB |
| Storage | 16 GB eMMC (`mmcblk2`), partitions below |
| Ports | seen on the board: USB-C `J5`, the board's only USB device port (ADB and RKDevTool, "Backup and restore"); 2× USB 3.0, stacked (the upper one works as a host; a mouse doesn't work in the lower one, cause unknown); 2× USB 2.0, stacked; Ethernet `NET0`; HDMI; SATA; CAN; an ADC header; microSD and SIM slots; DC jack `J1`; buttons `K1` FLASH, `K2` RST, `K3` PWR. RYD's 8897 specification lists more (LVDS, eDP, M.2, serial ports), not all fitted here |
| Power | 12 V DC (12–36 V accepted), 5.5/2.1 mm plug |
| Network in use | Wi-Fi only; both Ethernet ports (`eth0`, `eth1`) have no cable |
| OS | Ubuntu 22.04.5 LTS, the vendor's image, changed as listed in "Our changes to the vendor image" |
| Users | `root`, and `ftpuser` (uid 1000, with a password) for a weighing-scale application in `/userdata/blsRootPath` (291 MB). Nothing starts that application; `/home` is empty |
| Kernel | 5.10.209, Rockchip BSP |
| Desktop | GNOME, with Wayland and Xorg sessions installed |
| GPU driver | `libmali-bifrost-g52-g13p0-x11-gbm` 1.9, proprietary, for X11 and GBM: OpenGL ES 3.2, EGL 1.4. Its `mali/libEGL.so.1` and `mali/libgbm.so.1` are found before Ubuntu's and Mesa's (`/etc/ld.so.conf.d/00-aarch64-mali.conf`), except by Qt's KMS libraries; 03-video-spike.md and 04-ui-spike.md have what that means for Qt. Reading the GPU's `utilisation` file takes 100 ms |
| Video | `librockchip-mpp1` 1.5.0; GStreamer `rockchipmpp` plugin with `mppvideodec`, `mpph264enc`, `mpph265enc`, `mppjpegdec`, `mppjpegenc`; `librga2` 2.2.0. GStreamer itself is the vendor's 1.22.9, with development files. Decoding: H.265 to 2160p60, H.264 to 2160p30 (03-video-spike.md) |
| Display planes | `Smart0` (primary, at the bottom, RGB only), `Smart1` (RGB only), `Esmart0` and `Esmart1` (also NV12 and 10-bit NV15: the video planes), `Cluster0` (cursor) and `Cluster1` (AFBC); `zpos` 0–7 on all. The primary plane scales: Qt's framebuffer can differ from the screen mode (04-ui-spike.md) |
| Screens used | a 2560×1440 monitor (step 0.5); a Sharp TV from 2013 (step 0.6): 1080p at 60 Hz at most, prefers 1280×720 at 50 Hz, HDMI-CEC |
| mpv | 0.32 in `/usr/local/bin`; offers only `v4l2m2m-copy` hardware decoders |
| Held by apt | GStreamer base and GL packages, `libdrm` and others: the vendor's patched builds (`apt-mark showhold`) |
| Wi-Fi and Bluetooth | Realtek RTL8821CS. Wi-Fi over SDIO (module `RTL8821CS`); Bluetooth over UART `/dev/ttyS8` with the H5 protocol, attached by `rtk_hciattach`; firmware in `/lib/firmware/rtlbt` |
| Wi-Fi/Bluetooth start | `wifibt-init.service` runs `/usr/bin/wifibt-init.sh start` at boot |
| Audio | card 0: the analog RK809 codec. Card 1: HDMI (`rockchip,hdmi`, on `i2s@fe400000`), enabled in step 0.4; the vendor's device tree had `hdmi-sound` disabled |
| HDMI-CEC | `/dev/cec0`; input device `hdmi_cec_key` |
| Other inputs | PWM IR receiver (input device `fe6e0030.pwm`), `adc-keys`, the power key |
| Toolchain | gcc and g++ 11.4, CMake, Ninja, git |

## eMMC partitions

GPT, 512-byte sectors, 30,535,680 sectors in all (15.6 GB). The partitions follow each other without gaps. The start
sector is also the address RKDevTool uses.

| Partition | Label | Start sector | Size | Mounted at | Notes |
|---|---|---|---|---|---|
| | | `0x0` | 8 MB | | before `uboot`: protective MBR, GPT, the first-stage loader (DDR init and SPL) and Rockchip's vendor storage; in no partition, so a partition-only copy misses it |
| `mmcblk2p1` | `uboot` | `0x4000` | 4 MB | | bootloader: never touch |
| `mmcblk2p2` | `misc` | `0x6000` | 4 MB | | boot-mode flags (recovery); nearly empty |
| `mmcblk2p3` | `boot` | `0x8000` | 64 MB | | kernel and device tree (FIT image); changed in step 0.4 ("Changing the device tree") |
| `mmcblk2p4` | `recovery` | `0x28000` | 128 MB | | |
| `mmcblk2p5` | `backup` | `0x68000` | 32 MB | | empty (all zeros); the target of the restore rehearsal's write test |
| `mmcblk2p6` | `gzpeite` | `0x78000` | 16 MB | `/gzpeite` | vendor data (vfat) |
| `mmcblk2p7` | `logo_rk` | `0x80000` | 68 MB | `/mnt/logo` | boot logo (vfat) |
| `mmcblk2p8` | `rootfs` | `0xA2000` | 6.5 GB | `/` | 2.2 GB free since step 0.3 (0.4 GB before) |
| `mmcblk2p9` | `oem` | `0xDA2000` | 128 MB | `/oem` | ext4; its superblock changes at every mount ("Backup and restore") |
| `mmcblk2p10` | `userdata` | `0xDE2000` | 7.6 GB | `/userdata` | room for builds and media |
| | | `0x1D1EFC0` | 32 KB | | after `userdata`: the backup GPT |

The eMMC's hardware boot areas `mmcblk2boot0` and `mmcblk2boot1` (4 MB each) are empty; the RK3568 boots from the
main area.

## Access

- SSH as `root`, with the developer's key from the PC. sshd also accepts passwords, for `root` and `ftpuser`;
  kept on purpose (decisions log).
- On the network, only SSH (port 22) is open since step 0.3; ADB (5555) and FTP (21) are closed.
- USB: with the USB-C port `J5` cabled to a PC, Windows shows the running board as "Android ADB Interface" (USB
  `2207:0006`). `adb shell` over that cable gives a root shell without the network (tried 2026-11-13). It is the
  way to join the board to a new Wi-Fi network:
  `adb shell "nmcli device wifi connect '<SSID>' password '<password>' ifname wlan0"`, then
  `adb shell ip -4 addr show wlan0` for the new address. NetworkManager keeps every network joined this way and
  joins whichever is in range at boot.

## Our changes to the vendor image

Made in steps 0.3 to 0.5 (2026-11-13). Copies of the edited files as the vendor shipped them are in
`/root/rk3568-tv-orig/`.

| Change | Undo |
|---|---|
| Removed 202 packages that nothing of ours, the vendor's or the scale application uses: Docker, LLVM/Clang 14, Qt Creator, Qt 5 docs and tools, RealVNC server, `libraspberrypi-dev`, OpenCV's development files and `python3-opencv` with the science libraries they pulled in. apt's log of it is `/var/log/rk3568-tv-cleanup.log` | `apt install` the package |
| apt reads no source-package lists (the `deb-src` lines in `/etc/apt/sources.list` are commented out) and no translations, and keeps no source-package cache (`/etc/apt/apt.conf.d/99rk3568-tv-space`) | restore `sources.list` from the copy, delete the file |
| ext4's reserve for root on `/` lowered from 5 % to 1 % (`tune2fs -m 1 /dev/mmcblk2p8`) | `tune2fs -m 5 /dev/mmcblk2p8` |
| ADB no longer listens on the network: `/etc/profile.d/adbd.sh` no longer sets `ADB_TCP_PORT=5555`. `usbdevice.service` starts `adbd` and reads that file; ADB over USB is unaffected | restore the file, `systemctl restart usbdevice` |
| The FTP server for the scale application's folder is off (`systemctl disable --now vsftpd`) | `systemctl enable --now vsftpd` |
| `bt-recover` installed in `/usr/local/sbin` (Known faults) | delete it |
| `/userdata/dev` and `/userdata/media` created | |
| `boot`: the device tree enables `hdmi-sound` (step 0.4; image SHA-256 `46ecc4d7…`) | write the vendor's image, `/userdata/dev/hdmi-audio/p03-boot.orig.img` (the same as the backup's), back to `boot` |
| Qt Quick development packages installed (step 0.5): `qt6-declarative-dev` and QML modules, 29 Ubuntu packages, none held. Log: `/var/log/rk3568-tv-qtdev.log` | `apt purge` them |
| Test clips in `/userdata/media/test/` (step 0.5, 400 MB); the spike's workspace in `/userdata/dev/video-spike/` | delete them |
| Pictures for the UI spike in `/userdata/media/posters/` (step 0.6, 16 MB); its workspace in `/userdata/dev/ui-spike/` | delete them |

## Vendor files

The developer's vendor files sit in the repository's working folder under `RK3568/` and `scaleFirmware/`. They are
git-ignored: 19 GB, and not ours to publish. Examined on 2026-11-11:

| Item | What it is | Use for us |
|---|---|---|
| `RK3568/8897C_RYD-3568 Mainboard product specification.pdf.pdf` | RYD's specification of its 8897 mainboard | ports and power. Its OTG port, the lower USB 3.0, is not this board's: here it is the USB-C `J5` |
| `RK3568/RK356x Linux SDK 编译指导.pdf` | RYD's build guide for its SDK, in Chinese | background |
| `RK3568/rk356x_linux_sdk.tar.gz00` | part 1 of 3 of RYD's RK356x Linux SDK (March 2023, kernel 4.19.193). Parts 2 and 3 are missing, and this part fails its MD5 (an incomplete copy) | reference only: RYD's device trees for the board, `rk3568-8897-ddr4-v1-linux-{base,hdmi,edp}.dts`, can be read from this part |
| `scaleFirmware/RKDevTool_Release_v2.86/`, `scaleFirmware/RKDevTool_v3.19_for_window/` | Rockchip's flashing tool for Windows, with logs of earlier use | the restore route; v2.86 rehearsed on 2026-11-13 ("Backup and restore") |
| `scaleFirmware/DriverAssitant_v5.11/` (and v4.91) | Rockchip's USB driver installer | needed by RKDevTool |
| `…/RK3568-8897-Ubuntu2004-8G-20240521/update.img` | RYD's Ubuntu 20.04 firmware for the 8897 board, built 2024-08-21, kernel 5.10, CW2438 Wi-Fi module | not for this board (other partition layout, other Wi-Fi); contains an RK3568 loader (DDR init V1.11), which RKDevTool needs in its unticked `Loader` row |
| `scaleFirmware/RKDevTool_Release_v2.86/update.img` | an RK3568 Ubuntu 20.04 build with a read-only squashfs root, built 2025-01-22 | not for this board; contains an RK3568 loader, a candidate for maskrom mode (untested) |
| `…/boot.img`, `…/ubuntu-1804.img`, `…/ubuntu20.04/rootfs/ubuntu-2004.img` | RYD's 8897 kernel (4.19.193) and two ext4 root filesystems | not used |
| `scaleFirmware/pcs_1808_v1.8_v4.8/` | firmware for an RK1808 device | unrelated |

Why the board appears to be an 8897: the same two Ethernet ports, CAN and IR receiver, and these are the vendor files
the developer has for it. Its Wi-Fi chip, partition layout (`gzpeite`, `logo_rk`) and system (Ubuntu 22.04, kernel
5.10.209, a `gpio_gzpeite` driver) are GZPEITE's own. **No vendor image matches this board**; flashing one with
"Upgrade Firmware" would repartition the eMMC and replace the system. Our own backup is the only full restore source.

RYD's device trees enable `hdmi_sound` (`status = "okay"`) in both their HDMI and eDP variants; this board's device
tree had it disabled until step 0.4.

## Backup and restore

### The backup

Taken on 2026-11-11 and 2026-11-12. It is kept in two places outside the repository: on the developer's PC in
`C:\rk3568-backup\2026-11-11\`, and on a USB stick in `\rk3568-backup\2026-11-11\`, both verified on 2026-11-13.
It holds the board's secrets (the Wi-Fi password, SSH host keys, root's password hash, the board's addresses), so
it never goes into the repository or anywhere public. To check a copy: `sha256sum -c FILES.sha256` in its folder.

Since step 0.4 the board's `boot` differs from the backup's: the backup holds the vendor's original, without HDMI
sound.

| File | Content |
|---|---|
| `head.img.gz` | sectors `0x0` to `0x3FFF`: protective MBR, GPT, first-stage loader, vendor storage |
| `p01-uboot.img.gz` … `p09-oem.img.gz` | one image per partition, except the two below |
| `p08-rootfs.cNN.img.gz`, `p10-userdata.cNN.img.gz` | 256 MiB pieces; in order they give the partition: `cat p10-userdata.c*.img.gz \| gzip -dc` |
| `tail.img.gz` | the last 64 sectors: the backup GPT |
| `boot0.img.gz`, `boot1.img.gz` | the eMMC's boot areas (empty) |
| `SHA256SUMS` | SHA-256 of every uncompressed image, of every piece, and of `p08` and `p10` whole |
| `layout.txt` | start sector and size of every image |
| `backup.log`, `overnight.log`, `fsck.log` | how each region was read and checked, and the rehearsal below |
| `SHA256SUMS.board`, `usb.log` | the board's own record of the USB-stick copy |
| `FILES.sha256` | SHA-256 of every file in the folder, to check a copy |
| `tools/` | the scripts that took the backup |

How it was checked:

- For every region the board hashed exactly the bytes it sent, and the PC got the same SHA-256 and byte count.
  `rootfs` and `userdata` went through a USB stick in the board, since Wi-Fi was too slow.
- The regions that don't change were read a second time and matched, most recently on 2026-11-13.
- `rootfs` and `userdata` were copied while mounted, so their images look like the disk after a power cut.
  `e2fsck -fy` on a copy replays the journal, and both come out clean (`fsck.log`).

`gzpeite`, `logo_rk` and `oem` are mounted read-write at every boot. ext4 on `oem` then updates its superblock,
the start of its journal and its root folder's access time, so a fresh read of `oem` no longer matches its backup
even though no file changed. The FAT partitions `gzpeite` and `logo_rk` have stayed the same so far.

### Restore while Ubuntu runs: `dd`

1. Check the image on the PC (Git Bash, in the backup folder): `gzip -dc p03-boot.img.gz | sha256sum` must
   give the `p03-boot.img` line of `SHA256SUMS`.
2. Unmount the partition if it is mounted (`umount /oem` and so on). `/` can't be restored from the running
   system; use RKDevTool for it.
3. Write it, addressed by partition label so that a typo can't reach another partition:

   ```sh
   gzip -dc p03-boot.img.gz | ssh root@<board> 'dd of=/dev/disk/by-partlabel/boot bs=4M conv=fsync'
   ```

   Over Wi-Fi this suits the small images. `userdata` is too big for Wi-Fi: put its repaired image (below) on
   an NTFS-formatted USB stick and run the `dd` on the board. FAT32 can't hold a file over 4 GiB, and the
   board's kernel has no exFAT.
4. Check: `ssh root@<board> 'sync; echo 3 > /proc/sys/vm/drop_caches; sha256sum < /dev/disk/by-partlabel/boot'`
   gives the SHA-256 of the image written: the one from step 1, or for a repaired image (below) its own. Then
   reboot.

Before writing `rootfs` or `userdata`, join the pieces and repair the copy on the PC (in WSL), as `fsck.log`
did. The repair does what a boot after a power cut would do (replay the journal, clear orphaned files); done
first, the board starts from a clean filesystem.

```sh
cat p10-userdata.c*.img.gz | gzip -dc > p10-userdata.img
e2fsck -fy p10-userdata.img
```

`head` and `tail` lie outside the partitions (`dd of=/dev/mmcblk2 bs=512 count=16384` for `head`,
`seek=30535616` for `tail`). They hold the partition table and the first-stage loader; write them only if
those are damaged.

### Restore when Ubuntu doesn't boot: RKDevTool

Rehearsed on 2026-11-13 (`backup.log`):

- Reading back the start of the eMMC and the first 8 MiB of `boot` gave the backup's checksums.
- A 1 MiB test file written to `backup` landed exactly there, and no other region changed.
- `backup` was then zeroed again.

What it needs:

- Windows with Rockchip's USB driver (`DriverAssitant_v5.11`) and RKDevTool v2.86, both from the vendor files.
- A USB-A to USB-C cable: the A end in a USB-A port of the PC, the C end in the board's USB-C port `J5`, next to
  the USB 3.0 pair. The lower USB 3.0 port, which RYD's specification calls OTG, gave no connection with an A-to-A
  cable. The jumper beside `J5` was left as found.
- With Ubuntu running, RKDevTool then says "Found One ADB Device".

Loader mode:

- From Ubuntu: `systemctl reboot --reboot-argument=loader`. Windows shows "Rockusb Device" (USB `2207:350A`),
  RKDevTool says "Found One LOADER Device".
- Without Ubuntu: with the board off, hold FLASH (`K1`), switch it on, and keep holding for about 3 seconds.
  Tested on 2026-11-13: RKDevTool said "Found One LOADER Device". This is the way in when Ubuntu doesn't boot.
- ResetDevice (Advanced Function tab) leaves loader mode and boots normally.

Reading (Advanced Function tab): Start and Count in sectors, in hex, then ExportImage. The file goes to
`Output\ExportImage.img` in the tool's folder and replaces the one before. 8 MiB at a time works; 64 MiB was
refused ("device did not support to read").

Writing (Download Image tab):

1. Right-click the list and choose Clear Items. The tool loads the vendor's old rows from its `config.cfg`;
   never run them.
2. Add Item: name `Loader`, address `0x00000000`, path an RK3568 loader (below), **unticked**. Without a row
   named `Loader` the tool stops ("Loading loader failed") and closes. Ticked, the row would replace the board's
   own loader.
3. Add Item for each region to restore: address = its start sector (table above, or `layout.txt`), path = the
   uncompressed image (for `rootfs` and `userdata`, joined and repaired as above), ticked.
4. Tick Write by Address and press Run. The log shows "Test Device Success" and "Download image OK"; then the
   board restarts by itself.
5. Check each region over SSH, as in step 4 of the `dd` route.

Only the write to `backup` has been tested. Writing `head` or `uboot` this way, and maskrom mode (a board with no
working loader on the eMMC), have not. In maskrom mode the loader must first run from RAM, and which of the
vendor's loaders sets up this board's memory is unknown.

Never use the Upgrade Firmware tab (a vendor `update.img` would repartition the eMMC and replace the system),
EraseFlash, EraseAll, EraseLBA, Go Maskrom or Switch Storage.

The loader: each vendor `update.img` carries one. Its offset and length are 32-bit little-endian numbers at bytes
25 and 29 of the file. Both are already extracted in `loaders\` next to the backup, on the PC and on the stick:

```sh
f=update.img
off=$(od -A n -t u4 -j 25 -N 4 "$f" | tr -d ' ')
len=$(od -A n -t u4 -j 29 -N 4 "$f" | tr -d ' ')
tail -c +$((off + 1)) "$f" | head -c "$len" > loader.bin   # starts with "LDR "
```

## Changing the device tree

The kernel's device tree lives in the `boot` partition. The kernel can't apply overlays at runtime
(`CONFIG_OF_OVERLAY` is off), so a change means writing a new boot image. Step 0.4 did this once, to enable HDMI
sound.

The boot image is a FIT. A 0x600-byte header lists three parts, each with its position and SHA-256: `fdt` (at
0x800), `kernel` and `resource`. `resource`, in Rockchip's RSCE format, holds the boot logos and `rk-kernel.dtb`, a
second, identical copy of the device tree with its own SHA-1. The header has a `signature` node, but it contains
no signature: the image isn't signed (`androidboot.verifiedbootstate=orange`), and U-Boot checks only the
checksums. The image ends at 0x280b600. The rest of the 64 MB partition holds 14 MB of leftovers that nothing
reads.

[scripts/boot-dtb.sh](../scripts/boot-dtb.sh) changes both copies and all four checksums, and keeps every size and
position. It runs on the board, which has `dtc`, `fdtget` and `fdtput`. Its tests are
`sh scripts/tests/test-boot-dtb.sh`.

```sh
mkdir -p /userdata/dev/<change> && cd /userdata/dev/<change>
dd if=/dev/disk/by-partlabel/boot of=boot.orig.img bs=4M
sh boot-dtb.sh extract boot.orig.img fdt.dtb
cp fdt.dtb fdt.new.dtb
fdtput -t s fdt.new.dtb /hdmi-sound status okay                 # the change itself
dtc -q -I dtb -O dts -s fdt.dtb > a.dts; dtc -q -I dtb -O dts -s fdt.new.dtb > b.dts; diff a.dts b.dts
sh boot-dtb.sh replace boot.orig.img fdt.new.dtb boot.new.img   # checks before and after; refuses on doubt
dd if=boot.new.img of=/dev/disk/by-partlabel/boot bs=4M conv=fsync
sync; echo 3 > /proc/sys/vm/drop_caches; sh boot-dtb.sh verify /dev/disk/by-partlabel/boot
```

The new device tree may be smaller than the old one, which is padded with zeros, but not larger. Before writing,
have the way back ready:
- the original image, next to the new one;
- for a board that doesn't boot, RKDevTool in loader mode via the FLASH button, writing the original at `0x8000`
  ("Backup and restore").

Step 0.4's images are kept in `/userdata/dev/hdmi-audio/`: `p03-boot.orig.img` (the vendor's, `e435a705…`) and
`p03-boot.new.img` (`46ecc4d7…`).

## Known faults and fixes

### apt can't fetch a package (404)

apt's package lists date from the vendor's image. When the mirror has moved on to newer versions, a download fails
with `404 Not Found`, as `libinput-dev` did on 2026-11-13. Run `apt-get update` first. It touches neither the held
packages nor anything installed.

### Load average of 5 at idle

Not a fault. Five threads of the Wi-Fi driver (`RTW_XMIT_THREAD`, `RTW_RECV_THREAD`, `RTW_CMD_THREAD`, two
`RTWHALXT`) wait in uninterruptible sleep from boot on. Linux counts them in the load average; they use no CPU.

### Wi-Fi is slow and can stall

Uploads from the board over Wi-Fi ran at about 150 KB/s (SSH, 2.4 GHz, 2026-11-11). Once, a bulk transfer stopped
within a second of starting: the board stayed associated with the access point but passed no traffic, and
NetworkManager noticed only minutes later (state `CONNECTED_SITE`). Reconnecting fixed it, from the desktop's Wi-Fi
menu or with `nmcli connection up <name>`. The driver's power saving is at its highest setting
(`/sys/module/*/parameters/rtw_power_mgnt` is `2`), a likely suspect, not yet tested. Testing it means changing
Wi-Fi settings, so it waits for an Ethernet cable as the way back. Use Ethernet or a USB stick for large
transfers.

### Bluetooth won't turn on from the desktop

Symptom: the desktop's Bluetooth switch does nothing; `bluetoothd` logs `Failed to set mode: Failed (0x03)`;
`hciconfig hci0 up` says `Connection timed out`; `dmesg` shows `hci0: command 0x1003 tx timeout`.

Cause: Bluetooth was switched off in software (rfkill soft block, from the desktop's Bluetooth or airplane-mode
switch). That powers the chip down and it loses the firmware `rtk_hciattach` loaded at boot. Unblocking powers
it up again without firmware, and the `rtk_hciattach` still running from boot can't reach it.

Fix: run `bt-recover` as root. It is [system/bt-recover.sh](../system/bt-recover.sh), installed as
`/usr/local/sbin/bt-recover`, and takes the steps `wifibt-init.sh` takes at boot:

1. unblock;
2. stop the old `rtk_hciattach`;
3. power the chip off and on;
4. start `rtk_hciattach` again as the unit `rtk-hciattach`, which loads the firmware;
5. bring `hci0` up and power it on in BlueZ.

It exits 0 when Bluetooth is back. Run live on 2026-11-13, it took 2 seconds, and a scan found devices afterwards.

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
