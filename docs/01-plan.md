# Plan

Status on 2026-11-11: planning done, Phase 0 starts with step 0.2.

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
| CPU, RAM | 4× Cortex-A55, 4 GB | enough for a Qt Quick UI; not enough to decode 4K in software |
| Storage | 16 GB eMMC: `/` 6.5 GB and 93 % full, `/userdata` 7.6 GB | free space first (0.3); builds and media live in `/userdata` |
| GPU | Mali-G52, vendor driver `libmali-bifrost-g52-g13p0-x11-gbm` | OpenGL ES under X11 or straight on the screen (KMS/GBM); no Wayland build of the driver is installed |
| Video decoder | Rockchip MPP 1.5.0 with GStreamer elements (`mppvideodec`) | hardware decoding works through GStreamer |
| mpv | 0.32, offers only `v4l2m2m-copy` decoders | probably no hardware decoding on this kernel; a fallback to test, not the plan |
| Qt | Qt 6.2.4 and Qt 5.15.3 in Ubuntu's apt | no Qt build needed to start |
| HDMI audio | `hdmi-sound` disabled in the device tree; only the analog RK809 codec | must be enabled (0.4) |
| HDMI-CEC | `/dev/cec0` and an `hdmi_cec_key` input device | the TV's remote can drive the app |
| IR receiver | a PWM IR input device | a cheap IR remote can work |
| Wi-Fi, Bluetooth | Realtek RTL8821CS, Bluetooth over UART | works; one known fault after the desktop's toggle (02-board.md) |
| Toolchain | gcc 11.4, CMake, Ninja, git | we can build on the board itself |

## 4. Technical approach

### 4.1 The app

One C++20 application with a Qt Quick (QML) interface. C++ is the developer's language, and Qt Quick is built
for full-screen GPU-drawn interfaces that run without a desktop. We start with Ubuntu's Qt 6.2.4 from apt; a
newer Qt is built only if step 0.6 finds a blocker.

### 4.2 Display: no desktop

The app draws straight to the screen with Qt's EGLFS backend on KMS/GBM, which the vendor's Mali driver
supports. No compositor, no desktop: less memory, no window decorations, nothing for the viewer to fall into.
Fallback if EGLFS fails with this driver: a minimal X11 session that runs only the app. GNOME stays installed
until Phase 1 is done, as the way back.

### 4.3 Video: hardware decoding inside the UI

Decoding goes through Rockchip MPP via GStreamer's `mppvideodec`. Showing those frames inside a Qt Quick UI
without copying every 4K frame through the CPU is the main technical risk. Step 0.5 measures three candidates:

- **A. Qt Multimedia** (`MediaPlayer` and `VideoOutput`), which uses GStreamer underneath in Qt 6.2 and should
  pick `mppvideodec` by itself. Least code; may copy frames.
- **B. Our own GStreamer pipeline** ending in `appsink`, handing DMA-BUF frames to Qt Quick as textures. More
  code; no copies.
- **C. Video on its own display plane** (`kmssink`) with the Qt UI on a plane above it, transparent where the
  video shows. The classic TV-box design: the display hardware combines the two, nothing is copied.

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

- Start by building on the board, in `/userdata`, from VS Code Remote-SSH; step 0.7 settles the loop.
- CI on GitHub Actions' arm64 runners builds and tests every push and produces a `.deb` (step 1.8).
- Installing is `apt install ./rk3568-tv_<version>_arm64.deb`; Phase 3 adds updates from GitHub Releases.

### 4.7 Repository layout (planned)

```
app/          Qt Quick application: C++ in src/, QML in qml/
app/tests/    Qt Test
system/       systemd units, udev rules and scripts installed on the board
packaging/    Debian packaging
scripts/      developer scripts (deploy, logs)
docs/
```

## 5. Phases and steps

Each step ends with its "done when" met and one commit.

### Phase 0: groundwork and spikes

Decide the display and video stack on real measurements before writing the real UI.

- **0.1 Repository and plan.** Done when: this repository, its plan and its board notes are on GitHub.
- **0.2 Backup.** Copy the eMMC partitions to the PC (method chosen in the step: `dd` over SSH, or RKDevTool in
  loader mode) and learn the RKDevTool route that reflashes a board that no longer boots. Done when: the
  images are on the PC with matching checksums and the restore procedure is in 02-board.md.
- **0.3 Board housekeeping.** Free space on `/` (target: 2 GB free); create `/userdata/dev` and
  `/userdata/media`; close ADB on the network (port 5555 is open); decide on SSH password login now that key
  login works; a Bluetooth recovery script in `system/`. Done when: all of that holds after a reboot.
- **0.4 HDMI audio.** Enable `hdmi-sound` in the device tree (a changed DTB in the boot partition, or an overlay
  if the vendor's U-Boot reads them). Needs 0.2. Done when: `aplay -l` lists HDMI and a test tone plays on the
  TV after a reboot.
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
  back is written down.
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
| Hardware-decoded video can't be shown inside Qt Quick without copies | 4K stutters | spike 0.5 before any UI work; candidate C avoids the problem in hardware |
| The Mali driver doesn't work with Qt's EGLFS | no desktop-free start | spike 0.6; fallback to a minimal X11 session |
| HDMI audio can't be enabled | no sound on the TV | 0.4 early; fallbacks: Bluetooth speaker, analog output |
| A boot-partition change leaves the board unbootable | board out of action | backup and reflash procedure (0.2) before 0.4 |
| An apt upgrade replaces a vendor package | decoding or graphics break | keep apt's holds; never upgrade them |
| 16 GB eMMC fills up | builds and updates fail | 0.3; builds and media in `/userdata`; USB drives for big media |
| YouTube changes its interfaces | YouTube stops working | 2.3 picks the most stable route; it is the last source added |
| Bluetooth chip loses its firmware after the desktop toggle | no Bluetooth until fixed | known fix in 02-board.md; the app's own Bluetooth settings never power the chip off |

## 7. Open questions for the developer

1. The name. `rk3568-tv` is a working title; the app will need a name on screen.
2. A licence for the public repository (none yet, which means all rights reserved).
3. Which sources matter most after local files: IPTV, YouTube, Jellyfin? That orders Phase 2.
4. The TV or monitor: does it have 4K, HDR, HDMI-CEC? Its remote decides how much 1.7 gives.
5. Is there a Jellyfin or Plex server at home, or a NAS with media?
6. Is there an IR remote to use, or will one be bought?

## 8. Decisions log

| Date | Decision | Why |
|---|---|---|
| 2026-11-11 | Keep the vendor's Ubuntu 22.04 and build our own app; no new OS | the vendor image already has hardware decoding (MPP) and the Wi-Fi/Bluetooth drivers; community OSes (Armbian, LibreELEC) have no support for this board, and LibreELEC's RK3568 builds are still in testing with partial decoding |
| 2026-11-11 | C++20 and Qt Quick | the developer's language; Qt Quick draws a GPU interface without a desktop |
| 2026-11-11 | Start with Ubuntu's Qt 6.2.4 | in apt, nothing to build; revisit only if 0.5 or 0.6 finds a blocker |
| 2026-11-11 | Public repository on GitHub | the developer's choice; addresses and logins stay in git-ignored files |
