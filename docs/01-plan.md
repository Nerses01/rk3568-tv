# Plan

Status on 2026-11-13: steps 0.2 (backup), 0.3 (board housekeeping), 0.4 (HDMI audio), 0.5 (video spike: candidate
B, [03-video-spike.md](03-video-spike.md)), 0.6 (UI spike: EGLFS, the UI drawn at 1080p,
[04-ui-spike.md](04-ui-spike.md)) and 0.7 (development loop, [05-development.md](05-development.md)) are done. Phase 0
is complete. In Phase 1, steps 1.1 (the app skeleton, its tests, formatting and CI) and 1.2 (start at boot: the board
boots into the TV app, [02-board.md](02-board.md), "TV app or desktop") are done. Next: step 1.3, navigation and the
home screen.

## 1. Goal

Turn the RK3568 board into a TV box. It boots straight into a full-screen home screen on the TV, is driven from
the sofa with a remote or a keyboard, and plays video smoothly up to 4K with the chip's hardware decoder.

We keep the vendor's Ubuntu 22.04 image and build our own app on top of it. Porting another OS to this board was
considered and rejected (decisions log, §8).

## 2. Scope

**First version (Phases 0 and 1)**

- The board boots into the TV app; no desktop is visible.
- A home screen with large tiles, driven with arrows, OK, Back and Home.
- Local files and USB drives play, H.264, H.265 and VP9 up to 4K, decoded in hardware.
- Sound comes out of the TV over HDMI.
- Settings: Wi-Fi, Bluetooth devices, display, about.
- Control by Bluetooth or USB keyboard, by the TV's own remote (HDMI-CEC) and by an IR remote.

**Later (Phases 2 and 3)**

- IPTV playlists with a programme guide, a Jellyfin client, YouTube, a phone remote, updates from GitHub Releases.

**Out of scope**

- Netflix, Disney+, Prime Video and similar services. They need a certified device with hardware DRM
  (Widevine L1); this board has none.
- A new OS, kernel or bootloader for the board.
- Voice control, an app store, third-party apps.

## 3. What the board gives us

Surveyed over SSH on 2026-11-11; [02-board.md](02-board.md) has the details.

| | Found | What it means for us |
|---|---|---|
| Board | appears to be GZPEITE's build of RYD's 8897 mainboard | RYD's specification and device trees describe the hardware; no vendor image matches this board, so our own backup is the only restore source |
| CPU, RAM | 4× Cortex-A55, 4 GB | enough for a Qt Quick UI; not enough to decode 4K in software |
| Storage | 16 GB eMMC: `/` 6.5 GB (0.4 GB free, 2.2 GB after 0.3), `/userdata` 7.6 GB | builds and media live in `/userdata` |
| GPU | Mali-G52, vendor driver `libmali-bifrost-g52-g13p0-x11-gbm` | OpenGL ES under X11 or straight on the screen (KMS/GBM); no Wayland build of the driver is installed. Qt Quick on EGLFS holds 60 fps at 1080p, but can't draw 4K within one refresh (0.6) |
| Video decoder | Rockchip MPP 1.5.0 with GStreamer elements (`mppvideodec`) | hardware decoding works through GStreamer: H.265 up to 2160p60, H.264 up to 2160p30 (0.5) |
| mpv | 0.32, offers only `v4l2m2m-copy` decoders | probably no hardware decoding on this kernel; a fallback to test, not the plan |
| Qt | Qt 6.2.4 and Qt 5.15.3 in Ubuntu's apt | no Qt build needed to start |
| HDMI audio | `hdmi-sound` disabled in the vendor's device tree; only the analog RK809 codec | enabled in 0.4 with a changed device tree in `boot`; sound plays over HDMI |
| HDMI-CEC | `/dev/cec0` and an `hdmi_cec_key` input device | the TV's remote can drive the app |
| IR receiver | a PWM IR input device | a cheap IR remote can work |
| Wi-Fi, Bluetooth | Realtek RTL8821CS, Bluetooth over UART | works, but Wi-Fi uploads run at about 150 KB/s and stalled once under load; Bluetooth has one known fault after the desktop's toggle (02-board.md) |
| Ethernet | two gigabit ports, no cable yet | the fast, dependable link for large transfers and, later, streaming |
| Toolchain | gcc 11.4, CMake, Ninja, git | we can build on the board itself |

## 4. Technical approach

### 4.1 The app

One C++20 application with a Qt Quick (QML) interface. C++ is the developer's language, and Qt Quick is built
for full-screen GPU-drawn interfaces that run without a desktop. We use Ubuntu's Qt 6.2.4 from apt; steps 0.5 and
0.6 found no reason to build a newer one.

### 4.2 Display: no desktop

The app draws straight to the screen with Qt's EGLFS backend on KMS/GBM, which the vendor's Mali driver
supports. No compositor, no desktop: less memory, no window decorations, nothing for the viewer to fall into.
GNOME stays installed until Phase 1 is done, as the way back.

Decided in 0.6 ([04-ui-spike.md](04-ui-spike.md)):
- **EGLFS works.** The home screen holds 59.4 fps at 1080p60 while browsing, and keys arrive through libinput. The
  X11 fallback is dropped: it isn't needed, and Qt under X finds no EGL configuration with this driver.
- **The UI is drawn at 1920×1080.** On a 4K screen, the display controller scales it up (Qt's KMS `size` with
  atomic modesetting); the GPU manages only 28 fps drawing at 4K.
- **The app sets the screen mode itself**, 1920×1080 at 60 Hz by default, since a screen's preferred mode can be
  worse: the developer's TV prefers 720p50.
- **The app links the Mali EGL, GLES and GBM libraries itself**, or Qt loads Mesa's GBM and fails.

### 4.3 Video: hardware decoding inside the UI

Decoding goes through Rockchip MPP via GStreamer's `mppvideodec`. Showing those frames inside a Qt Quick UI
without copying every 4K frame through the CPU is the main technical risk. Step 0.5 measures three candidates:

- **A. Qt Multimedia** (`MediaPlayer` and `VideoOutput`), which uses GStreamer underneath in Qt 6.2 and should
  pick `mppvideodec` by itself. Least code; may copy frames.
- **B. Our own GStreamer pipeline** ending in `appsink`, handing DMA-BUF frames to Qt Quick as textures. More
  code; no copies.
- **C. Video on its own display plane** (`kmssink`) with the Qt UI on a plane above it, transparent where the
  video shows. The classic TV-box design: the display hardware combines the two, nothing is copied.

Decided in 0.5: **B**. It showed every frame up to 2160p30 with the UI at 60 fps; A copies frames and the UI drops to
6–19 fps; C halves the UI's frame rate unless both planes share one atomic commit
([03-video-spike.md](03-video-spike.md)).

### 4.4 Input

Everything maps to one remote-control model: arrows, OK, Back, Home, Play/Pause, volume. Sources:

- keyboards (USB, Bluetooth), read by Qt through evdev or libinput;
- the TV's remote through HDMI-CEC (`/dev/cec0`);
- an IR remote through the board's IR receiver;
- later, a phone, through a web page the box serves on the home network.

### 4.5 System integration

- A systemd unit starts the app at boot, as an unprivileged user `tv`.
- Wi-Fi through NetworkManager, Bluetooth through BlueZ, USB drives through udisks2, all over D-Bus.
- The vendor's patched packages (MPP, Mali, RGA, GStreamer, libdrm) stay as they are; apt already holds them.

### 4.6 Build, deploy, update

- Build on the board, in `/userdata`, from the PC (decided in 0.7, [05-development.md](05-development.md)). The
  sources stay on the PC. `scripts/board.sh deploy` copies `app/` over SSH, builds it on the board and restarts it
  on the screen. Screenshots, key presses and the log come back over SSH, so the TV can stay off.
- Large transfers (backups, test media) go over Ethernet or a USB drive; the board's Wi-Fi is too slow for them.
- CI on GitHub Actions' arm64 runner (`ubuntu-22.04-arm`, the board's Ubuntu and Qt) checks the formatting, builds
  and tests every push (step 1.1); it will also produce a `.deb` (step 1.8). Its checks live in `scripts/ci.sh`,
  which also runs on the PC in Docker.
- Installing is `apt install ./rk3568-tv_<version>_arm64.deb`; Phase 3 adds updates from GitHub Releases.

### 4.7 Repository layout (planned)

```
app/          Qt Quick application: C++ in src/, QML in qml/
app/tests/    Qt Test for the C++, Qt Quick Test for the QML (qml/)
system/       systemd units, udev rules and scripts installed on the board
system/tests/ tests for those scripts, with stub commands (plain sh)
packaging/    Debian packaging
scripts/      developer scripts (deploy, logs, the boot image's device tree, formatting, CI)
scripts/tests/ tests for those scripts
.github/      the CI workflow
spikes/       throwaway measurement code from the spikes, kept to reproduce their numbers (no tests)
docs/
```

## 5. Phases and steps

Each step ends with its "done when" met and one commit.

### Phase 0: groundwork and spikes

Decide the display and video stack on real measurements before writing the real UI.

- **0.1 Repository and plan.** Done when: this repository, its plan and its board notes are on GitHub.
- **0.2 Backup.** Copy every sector of the eMMC to the PC (outside the repository) with `dd` over SSH: one
  gzip-compressed image per region, from the 8 MB before `uboot` to the backup GPT at the end, plus the eMMC's two
  boot areas. The board hashes exactly the bytes it sends; the PC must get the same SHA-256 and byte count.
  Regions nothing writes to are read a second time and must match again; `/` and `/userdata` are copied while
  mounted, so their images are checked with `e2fsck` instead. The mounted partitions go over Ethernet or a USB
  drive, since Wi-Fi is too slow. Then rehearse the route for a board that no longer boots: RKDevTool (from the
  vendor files) in loader mode reads regions back to compare checksums; optionally it writes the empty `backup`
  partition back. Done when: every region is on the PC with matching checksums, the rehearsal has passed, and
  the restore procedure is in 02-board.md.
- **0.3 Board housekeeping.** Free space on `/` (target: 2 GB free); create `/userdata/dev` and
  `/userdata/media`; close ADB on the network (port 5555 is open); decide on SSH password login now that key
  login works; a Bluetooth recovery script in `system/`. Done when: all of that holds after a reboot. The test
  of whether the Wi-Fi driver's power saving causes the stalls was left out: it needs an Ethernet cable as the
  way back, and waits for one.
- **0.4 HDMI audio.** Enable `hdmi-sound` in the device tree (a changed DTB in the boot partition, or an overlay
  if the vendor's U-Boot reads them). RYD's own device trees for this board set it to `okay` on the same I2S
  controller, so that status may be the only change. Start from the board's own DTB, taken from the backup of
  `boot`, not from RYD's, whose kernel (4.19) differs. Needs 0.2. Done when: `aplay -l` lists HDMI and a test
  tone plays on the TV after a reboot.
- **0.5 Video spike.** Freely licensed test clips (for example the Blender Foundation's open movies) in
  H.264, H.265 and VP9 at 1080p and 4K. First `gst-launch-1.0` with `mppvideodec` straight to the screen,
  measuring CPU use and dropped frames; then candidates A, B and C (§4.3) in a throwaway Qt Quick app. Done
  when: the choice and its numbers are in the decisions log.
- **0.6 UI spike.** The same throwaway app on EGLFS with the Mali driver: a grid of tiles scrolling at 60 fps
  at 1080p and 4K output, keyboard input working, no desktop running. Fallback: the minimal X11 session. Done
  when: the choice is in the decisions log.
- **0.7 Development loop.** Build, install and restart from VS Code in one command; logs through `journalctl`.
  Done when: a QML change is on the TV in under a minute.

### Phase 1: first version

- **1.1 App skeleton.** `app/` with CMake, Qt Quick, C++20 and Qt Test; clang-format and qmlformat; GitHub
  Actions builds on an arm64 runner and runs the tests.
- **1.2 Start at boot.** The systemd unit and the `tv` user; the desktop off by default; how to get the desktop
  back is written down. The vendor's `hdmi_hotplug.service` starts GNOME on every HDMI hotplug and must not
  (02-board.md). A stopped app exits with status 1, and `XDG_RUNTIME_DIR` must be set (05-development.md).
- **1.3 Navigation and home screen.** The focus model (arrows, OK, Back, Home) and a 10-foot design: large
  text, safe margins, scaled for 1080p and 4K.
- **1.4 Player.** The video path from 0.5; play, pause, seek, audio and subtitle tracks; resume where you
  stopped.
- **1.5 Local media.** `/userdata/media` and USB drives; folders, thumbnails.
- **1.6 Settings.** Wi-Fi, Bluetooth (scan, pair, forget), display resolution, about and version.
- **1.7 Remotes.** HDMI-CEC: the TV's remote keys drive the app, and the TV and box switch on together. The IR
  remote's keys mapped.
- **1.8 Package.** CI produces the `.deb`. Done when: the vendor image plus `apt install` of the package gives
  the whole TV.

### Phase 2: online sources

- **2.1 IPTV.** M3U playlists, a channel list, a programme guide from XMLTV.
- **2.2 Jellyfin.** A client for the developer's server, if there is one (§7).
- **2.3 YouTube.** A spike first: YouTube's TV web interface in a browser view (software decoding, so check
  that 1080p is smooth), against a native client that resolves streams and plays them in our hardware
  player (smooth 4K, but it breaks when YouTube changes and must respect YouTube's terms).
- **2.4 Phone remote.** A small web page served by the box on the home network.

### Phase 3: polish

- **3.1 Updates.** Check for and install new versions from GitHub Releases, from the settings screen.
- **3.2 Everyday behaviour.** Screensaver, standby and wake together with the TV, boot time.
- **3.3 Other boards.** Optional: other RK3566 and RK3568 boards with a Rockchip Ubuntu image.

## 6. Risks

| Risk | Effect | What we do |
|---|---|---|
| Hardware-decoded video can't be shown inside Qt Quick without copies | 4K stutters | settled by spike 0.5: candidate B shows 2160p30 without copies; 2160p60, 10-bit and VP9 are confirmed in 1.4 |
| The Mali driver doesn't work with Qt's EGLFS | no desktop-free start | settled by spike 0.6: it works, 60 fps at 1080p, once the app links the Mali libraries itself |
| The vendor's `hdmi_hotplug.service` starts GNOME on every HDMI hotplug | switching the TV off and on brings the desktop over the app | settled by step 1.2: TV mode masks it, desktop mode unmasks it |
| On a 4K screen, video drawn in the UI (candidate B) is limited to the UI's 1080p framebuffer | 4K video shows at 1080p | step 1.4: a 4K framebuffer while playing, or video on its own plane (candidate C); tested on the developer's 4K monitor at the office |
| HDMI audio can't be enabled | no sound on the TV | 0.4 early; fallbacks: Bluetooth speaker, analog output |
| A boot-partition change leaves the board unbootable | board out of action | backup and reflash procedure (0.2); the FLASH button reaches loader mode without Ubuntu (tested in 0.4); `scripts/boot-dtb.sh` checks an image before it is written |
| The backup is lost or damaged | no way back: no vendor image matches this board | checksums in the backup folder; a second copy off the PC |
| The board's Wi-Fi is slow and stalls | transfers and SSH sessions die; streaming suffers | Ethernet or a USB stick for large transfers; power-saving test once an Ethernet cable is in |
| An apt upgrade replaces a vendor package | decoding or graphics break | keep apt's holds; never upgrade them |
| 16 GB eMMC fills up | builds and updates fail | 0.3; builds and media in `/userdata`; USB drives for big media |
| YouTube changes its interfaces | YouTube stops working | 2.3 picks the most stable route; it is the last source added |
| Bluetooth chip loses its firmware after the desktop toggle | no Bluetooth until fixed | known fix in 02-board.md; the app's own Bluetooth settings never power the chip off |

## 7. Open questions for the developer

1. The name. `rk3568-tv` is a working title; the app will need a name on screen.
2. A licence for the public repository (none yet, which means all rights reserved).
3. Which sources matter most after local files: IPTV, YouTube, Jellyfin? That orders Phase 2.
4. The TV or monitor: does it have 4K, HDR, HDMI-CEC? Its remote decides how much 1.7 gives. Partly answered in
   0.6: the TV in use, a Sharp from 2013, has 1080p at most and HDMI-CEC. A 4K monitor at the developer's office
   is available for testing, first on 2026-11-16.
5. Is there a Jellyfin or Plex server at home, or a NAS with media?
6. Is there an IR remote to use, or will one be bought?
7. Can GZPEITE supply this board's factory image and its kernel source? Not needed now; it would give a second
   restore source and the board's exact device tree.

## 8. Decisions log

| Date | Decision | Why |
|---|---|---|
| 2026-11-11 | Keep the vendor's Ubuntu 22.04 and build our own app; no new OS | the vendor image already has hardware decoding (MPP) and the Wi-Fi/Bluetooth drivers; community OSes (Armbian, LibreELEC) have no support for this board, and LibreELEC's RK3568 builds are still in testing with partial decoding |
| 2026-11-11 | C++20 and Qt Quick | the developer's language; Qt Quick draws a GPU interface without a desktop |
| 2026-11-11 | Start with Ubuntu's Qt 6.2.4 | in apt, nothing to build; revisit only if 0.5 or 0.6 finds a blocker |
| 2026-11-11 | Public repository on GitHub | the developer's choice; addresses and logins stay in git-ignored files |
| 2026-11-11 | Back up with `dd` over SSH, one compressed image per region; rehearse the restore with RKDevTool | no reboot or cable for the copy, and the unmounted regions come out exact; RKDevTool proves the route for a board that no longer boots |
| 2026-11-11 | Vendor files stay in the working folder, git-ignored; none is used as a restore source | 19 GB and not ours to publish; no vendor image matches this board's partitions or Wi-Fi; we use RKDevTool, its USB driver, an RK3568 loader and RYD's device trees as reference |
| 2026-11-12 | `rootfs` and `userdata` copied through a USB stick in the board, in 256 MiB pieces hashed on the board | Wi-Fi would have taken about 6 hours and had stalled under load; the stick needs no network, and the pieces let an interrupted copy resume |
| 2026-11-13 | Restore route for a board that doesn't boot: RKDevTool v2.86 in loader mode over the USB-C port `J5`; Download Image with Write by Address and an unticked `Loader` row | rehearsed: read-backs matched the backup and a test write landed exactly in `backup`; the Upgrade Firmware tab and the vendor images stay unused |
| 2026-11-13 | Free space on `/` by removing unused software (Docker, LLVM/Clang 14, Qt Creator, Qt 5 docs and tools, RealVNC, OpenCV's development files), apt's source lists and translations, and most of ext4's root reserve | `/` had 0.4 GB free; nothing of ours, the vendor's or the scale application uses any of it, and apt can bring any of it back. `clang-format` (step 1.1) can run on the PC and in CI |
| 2026-11-13 | SSH keeps accepting passwords | the developer's choice |
| 2026-11-13 | Only SSH open on the network: ADB over USB only, the FTP server off | fewer ways in for others; ADB over the USB cable stays as a way in for us |
| 2026-11-13 | The Wi-Fi power-saving test leaves step 0.3 | changing Wi-Fi settings needs Ethernet as the way back, and no cable is connected |
| 2026-11-13 | A second copy of the backup on a USB stick, with `FILES.sha256` in each copy | the risk "the backup is lost or damaged"; the stick is offline |
| 2026-11-13 | HDMI audio: change the device tree inside the existing boot image (both copies, all checksums, sizes and positions unchanged) with `scripts/boot-dtb.sh`, rather than rebuild the image | the kernel can't apply overlays; the image isn't signed; changing only what must change leaves the vendor's kernel, logos and layout as they were |
| 2026-11-13 | Video in the UI: candidate B, our own GStreamer pipeline (`mppvideodec ! queue ! appsink`) whose DMA-BUF frames are drawn as EGLImages in Qt Quick's render pass | 1080p30 and 2160p30, H.264 and H.265: 1799–1800 of 1800 frames shown, UI at 60 fps, about 55 % of one core. A (Qt Multimedia): UI at 19 fps (1080p) and 6 fps (2160p). C (`kmssink` under Qt): UI at 25–30 fps, 17–38 % of frames lost ([03-video-spike.md](03-video-spike.md)) |
| 2026-11-13 | No Qt Multimedia for video | it copies every frame, and Ubuntu's build needs EGL 1.5 functions that the vendor's Mali EGL 1.4 lacks |
| 2026-11-13 | Spike code is kept in `spikes/`, without tests | it is measurement code, not product code; kept so that the decisions' numbers can be reproduced |
| 2026-11-13 | The UI runs on EGLFS (`eglfs_kms`) with the Mali driver and no desktop; the X11 fallback is dropped | 0.6: the home screen holds 59.4 fps at 1080p60 while browsing, with about 1 % late frames, nearly all from uploading background stills; keys arrive through libinput. Qt under X finds no EGL configuration with this driver (0.5) ([04-ui-spike.md](04-ui-spike.md)) |
| 2026-11-13 | The UI is drawn at 1920×1080; a 4K screen gets it scaled by the display controller (Qt's KMS `size`, atomic modesetting) | at 3840×2160 the GPU manages 28 fps, 44 fps with no pictures, and a faster memory clock doesn't help; the scaler costs the GPU nothing |
| 2026-11-13 | The app sets the screen mode itself (1920×1080 at 60 Hz by default) | Qt's default is the screen's preferred mode, and the developer's TV prefers 1280×720 at 50 Hz |
| 2026-11-13 | The app links the Mali EGL, GLES and GBM libraries itself, ahead of Qt and with `--no-as-needed` | Qt's KMS libraries have RUNPATH `$ORIGIN` and otherwise load Mesa's GBM, and Qt stops with "Could not create GBM device" |
| 2026-11-13 | Development loop: the sources stay on the PC; `scripts/board.sh deploy` sends `app/` over SSH as a tar stream, builds it on the board with CMake and Ninja and restarts it as the transient systemd unit `rk3568-tv-dev`; VS Code tasks call it. No Remote-SSH checkout on the board | a QML change is on screen in 23 s; one copy of the repository, where git and Claude Code work; no cross-compiling sysroot to keep; the app's log goes to the journal ([05-development.md](05-development.md)) |
| 2026-11-13 | Checking without the TV: screenshots with ffmpeg's `kmsgrab`, key presses through a `uinput` keyboard, and HDMI forced on with the last screen's EDID when the TV is off | the developer prefers not to sit at the TV; `kmsgrab` reads what Qt drew on the Mali GPU; `uinput` keys take a real keyboard's path; all of it is undone by `board.sh stop` or a reboot |
| 2026-11-13 | CI on GitHub's `ubuntu-22.04-arm` runner with Ubuntu's own Qt 6.2.4 packages; every check in `scripts/ci.sh`, which runs the same in a local Docker image built from `scripts/ci-deps.sh` | the runner has the board's Ubuntu release, architecture and Qt packages, so a pass there means something for the board; arm64 runners are free for public repositories; the developer can run CI before pushing, and Claude can without pushing |
| 2026-11-13 | The app's QML and its C++ types form one static QML module (`rk3568tv_ui`, URI `Rk3568Tv`, resources under `/qt/qml`), linked by the app and by the tests | the tests run the app's own code, QML included; `/qt/qml` is Qt 6.5's default, so an upgrade only removes code; Qt 6.2 needs the import path set and `import Rk3568Tv` inside the module (05-development.md) |
| 2026-11-13 | Every input maps to one remote-control model: `RemoteKeys` turns a Qt key into an action (up, down, left, right, ok, back, home, menu, play/pause, volume) | keyboards, the TV's remote over CEC and an IR remote all arrive as Qt keys (04-ui-spike.md, finding 4); one table, tested, for all of them |
| 2026-11-13 | Work stays on `main` now that CI exists: one commit per step; CI's checks run in Docker before each commit | the developer's choice for a solo project: no pull-request overhead, and `main` stays green |
| 2026-11-13 | The app runs from boot as the system user `tv` (groups video, render, input, audio), in a logind session on tty1 (`PAMName=login`), in place of tty1's login prompt | every device it needs belongs to those groups; the session gives it `XDG_RUNTIME_DIR`; on its own tty Qt switches the console keyboard off, so keys reach only the app and Ctrl+Alt+Del can't restart the board |
| 2026-11-13 | TV mode: default target `multi-user.target`, `rk3568-tv.service` enabled, the vendor's `hdmi_hotplug.service` masked; `rk3568-tv-mode tv` and `rk3568-tv-mode desktop` switch, and GNOME stays installed. The app's unit and GNOME's conflict | one command each way, tested with reboots both ways; nothing of the vendor's is removed; networking and SSH are wanted by `multi-user.target`; the desktop takes 320 MB more memory |
| 2026-11-13 | The app quits through its event loop on SIGTERM and SIGINT (`UnixSignals`) | Qt's own handler on EGLFS exits with status 1, so systemd counted every stop as a failure, and none of the app's shutdown ran |
| 2026-11-13 | The unit restarts the app 3 s after any exit, with no start limit; before each start, `rk3568-tv-screen` stands in for a switched-off TV with the last screen's EDID | a TV box has nobody to restart its app; with the TV off at boot, the app would otherwise find no screen |
| 2026-11-13 | A deploy installs the build and restarts the real unit; the transient development unit is gone | development runs the app exactly as the board runs it from boot, so nothing differs between the two; until the package of step 1.8, the last deploy is the installed app |
| 2026-11-13 | Formatting: clang-format 14 with a Qt-like style at 120 columns, and qmlformat 6.2.4, both Ubuntu 22.04's, checked in CI; no arrow functions in QML; no qmllint for now | the same versions in CI, Docker and on the board, so the check never disagrees with the formatter; qmlformat 6.2 corrupts arrow functions; qmllint 6.2 reports Qt's own `Qt` object as an error |
