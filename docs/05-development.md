# Development (steps 0.7, 1.1 and 1.2)

The app is edited on the PC, then built and run on the board. One command copies it over, builds it there and
restarts it on the screen; a QML change is on screen in about half a minute. Logs, screenshots and key presses come
back over SSH, so a change can be checked without sitting at the TV, even with the TV switched off.

Formatting, the tests and CI run the same checks everywhere: on GitHub, in Docker on the PC, and on the board
("Tests, formatting and CI" below).

## Setup

- SSH key login to the board as `root` (02-board.md, "Access").
- A file `.env` in the repository's root, which git ignores: `BOARD=root@<the board's address>`.
- On Windows: Git for Windows, for Git Bash. The scripts are POSIX `sh`.
- For formatting and CI on the PC: Docker. The PC needs no Qt.

## The app's code

| Where | What |
|---|---|
| `app/CMakeLists.txt` | the app `rk3568-tv`, and the static QML module `rk3568tv_ui` (URI `Rk3568Tv`) that the app and the tests share |
| `app/src/` | C++: `main.cpp`. Types QML uses: `RemoteKeys` (keys to remote-control actions), `SystemInfo`, `VideoLibrary` (the video files), `VideoPlayer` (playback and drawing), `Wifi` (through `nmcli`), `Bluetooth` (through `bluetoothctl`), `DisplaySettings` (the screen mode). C++ QML doesn't see: `UnixSignals` (a clean quit when systemd stops the app), `ResumePositions`, `Command` (runs `nmcli` and `bluetoothctl`; the tests swap in stubs through `RK3568_TV_NMCLI` and `RK3568_TV_BLUETOOTHCTL`) |
| `system/` | what the board runs: the unit `rk3568-tv.service`, `install.sh`, `rk3568-tv-mode`, `rk3568-tv-screen`, the polkit rule `rk3568-tv.pkla`; tests in `system/tests/` |
| `app/qml/` | QML: `Main.qml` (the window), `Theme.qml` (the look), `PageStack.qml` and `Page.qml` (navigation), the pages (`HomePage`, `VideosPage`, `PlayerPage`, `SettingsPage`, `WifiPage`, `PasswordPage`, `BluetoothPage`, `DisplayPage`, `ConfirmModePage`, `ChoicesPage`, `AboutPage`) and their parts (`Tile`, `MenuRow`, `Clock`, `OnScreenKeyboard`) |
| `app/tests/` | Qt Test for the C++ (`tst_*.cpp`), Qt Quick Test for the QML (`qml/tst_*.qml`) |

Qt 6.2 needs a few things that later versions don't:
- The module's resources sit under `qrc:/qt/qml`, and the app and the QML tests add that import path themselves.
- A QML file in the module imports the module (`import Rk3568Tv`) to see its C++ types.
- A header with `QML_ELEMENT` or `QML_SINGLETON` includes `<QtQml/qqml.h>`.

## UI conventions (step 1.3)

The UI is made for a TV about 3 m away and is driven only by a remote or a keyboard: arrows, OK, Back and Home.

- **Layout units:** the UI is laid out at 1920×1080, and `Main.qml` scales it to the screen. Take every size, colour,
  font and duration from `Theme`. Text is at least `Theme.textCaption` (28), and everything stays inside the safe
  area (`Theme.safeX`, `Theme.safeY`). `tst_tenfoot.qml` checks both rules on every page; a new page goes into that
  test.
- **Pages:** a screen is a `Page`, which provides the title, the clock and the safe area. A page opens another with
  `stack.push(component, { "title": ... })`.
  - `Main.qml` handles Back and Home for every page: Back pops one page, Home goes back to the first.
  - A page that comes back gets its focus back where it left it.
- **Lists:** use a `ListView` with `focus: true`, `interactive: false` (there is no pointer) and
  `keyNavigationEnabled: true`. Qt 6.2 ties key navigation to `interactive`, so without it the arrows do nothing.
  - OK is handled in the list's `Keys.onPressed`, through `RemoteKeys`. Every other key is passed on with
    `event.accepted = false`.
  - The delegate shows the focus with `highlighted: ListView.isCurrentItem && view.activeFocus`.
- **Focus** shows by shape as well as colour: a white frame, and for tiles a 6 % larger size.
- **Strings** visible to the viewer go through `qsTr()`.
- **Keys without an action** are logged ("a key without an action: 0x…"), so that a remote's codes can be read with
  `board.sh logs`.

## Commands

From the repository's root, or as VS Code tasks (Terminal → Run Task; Ctrl+Shift+B deploys):

| Command | VS Code task | What it does |
|---|---|---|
| `sh scripts/board.sh deploy` | Board: deploy (Ctrl+Shift+B) | copies `app/` to the board, builds it there, restarts it on the screen |
| `sh scripts/board.sh test` | Board: run the tests | copies `app/` to the board, builds everything there and runs the tests, offscreen; the running app stays |
| `sh scripts/board.sh shot [FILE]` | Board: screenshot | the board's screen as a PNG, by default `screenshots/latest.png` (git ignores the folder) |
| `sh scripts/board.sh keys KEY...` | Board: press keys | presses keys on the board, e.g. `keys right right down enter`; `right:1500` holds a key, `wait:500` pauses |
| `sh scripts/board.sh logs [-f]` | Board: follow the log | the app's log from the journal: its own lines (`journalctl -t rk3568-tv`, not `-u`: it runs in a login session, which the journal files them under), systemd's about the unit, and the decoder library's (`mpp`). The player logs every file it plays, and on stopping how many frames arrived and how many were DMA-BUFs |
| `sh scripts/board.sh stop` | Board: stop the app, desktop back | stops the app and starts GNOME, until the next boot or deploy |
| `sh scripts/board.sh mode [tv\|desktop]` | | what the board boots into: shows it, or switches it (02-board.md, "TV app or desktop") |

Keys: `up`, `down`, `left`, `right`, `enter`, `back`, `home`, `menu`, `esc`, `space`, `playpause`, `volumeup`,
`volumedown` ([scripts/board-keys.c](../scripts/board-keys.c)). VS Code opens the build's error messages at the
right line in the PC's files.

Measured on 2026-11-13 over Wi-Fi:

| | Time |
|---|---|
| First deploy (configures and builds everything) | 41 s |
| Deploy after a QML change | 23 s |
| Deploy with nothing changed (install and restart only; since step 1.2) | 8 s |
| QML change, deployed, keys pressed, screenshot back | 31 s |

## What happens on the board

`deploy` sends `app/`, `system/` and the board's two scripts to `/userdata/dev/rk3568-tv` as a tar stream. Each
file keeps its time, so the build redoes only what changed. Then [scripts/board-run.sh](../scripts/board-run.sh):

1. Builds with CMake and Ninja in `/userdata/dev/rk3568-tv/build`, and builds the key tool.
2. Installs the build with [system/install.sh](../system/install.sh), together with the unit and its scripts, as
   the board runs them from boot (step 1.2). A development build therefore runs exactly like the app at boot: same
   unit, same user `tv`, same screen mode (`/var/lib/rk3568-tv/kms.json`, which Settings, Display changes).
3. Masks the vendor's `hdmi_hotplug.service` until the next reboot, in case the board is in desktop mode. Otherwise
   every HDMI hotplug would start GNOME, which would stop the app (02-board.md, "An HDMI hotplug starts the
   desktop"). TV mode masks it for good anyway.
4. Restarts `rk3568-tv.service`, which stops GNOME if it runs. Before the app starts, the unit stands in for a
   switched-off TV: HDMI forced on with the last screen's EDID, so the app runs, screenshots work, and switching
   the TV on shows the app (02-board.md, "TV app or desktop").

   If the app doesn't keep running, its log is shown and the deploy fails.

`board.sh shot` reads the screen with ffmpeg's `kmsgrab`: the framebuffer the display shows, whoever drew it. With
the TV off it only works while the app runs, since GNOME doesn't stand in for the screen. `board.sh keys` presses
keys through a virtual keyboard on `/dev/uinput`. They take the path a real keyboard's keys take (kernel, udev,
libinput, Qt). Each call waits 2 s for libinput to find the keyboard.

`stop` stops the app and starts GNOME, until the next boot or deploy. The board's mode stays as it was.

## Known rough edges

- **The app doesn't run on Windows.** The PC edits, formats and runs CI in Docker; the app itself runs on the
  board.
- **The deploy is the installed app.** Until step 1.8 brings a package, the last deploy is what the board runs
  from boot.

## Tests, formatting and CI

[scripts/ci.sh](../scripts/ci.sh) holds everything CI checks:
1. the formatting;
2. the app, built with warnings as errors, and its tests;
3. the tests of the shell scripts and the board's tools.

It runs in Ubuntu 22.04, the board's release, so with the same Qt 6.2.4. [scripts/ci-deps.sh](../scripts/ci-deps.sh)
installs the packages it needs.

| Where | How | Takes |
|---|---|---|
| GitHub, every push and pull request | [.github/workflows/ci.yml](../.github/workflows/ci.yml), on GitHub's arm64 runner `ubuntu-22.04-arm` | 48 s, packages included (first run, 2026-11-13) |
| The PC, before a commit | `sh scripts/in-docker.sh sh scripts/ci.sh` (VS Code task "CI in Docker") | 67 s from scratch, 17 s after |
| The board, the app's tests only | `sh scripts/board.sh test` | 56–74 s |

`scripts/in-docker.sh` builds an Ubuntu 22.04 image with CI's packages on first use, which takes about two
minutes. It builds the image again whenever `ci-deps.sh` changes.

**Formatting:** `sh scripts/format.sh` formats the C++ with clang-format 14, using [.clang-format](../.clang-format)
(Qt-like, 120 columns), and the QML with qmlformat 6.2.4. On Windows, run it as
`sh scripts/in-docker.sh sh scripts/format.sh` (VS Code task "Format"). CI runs `format.sh --check`.
- **No arrow functions in QML, and no `for (let ...)` loops:** qmlformat 6.2 turns both into invalid code.
  - Write `function (event) { ... }`.
  - Over arrays, loop with `for (const x of list)`. Over QML lists such as `children`, which Qt 6.2 can't iterate,
    use `for (var i = 0; ...)`.
- **No qmllint:** Qt 6.2's qmllint reports Qt's own `Qt` object as unqualified access.

**Tests:** the app's tests run offscreen with Qt Quick's software renderer, so they need no screen and no GPU.
The player's test makes its own videos with GStreamer (VP8, two sound tracks, subtitles). It plays them with
software decoders in CI and with the hardware decoder on the board, and its sound goes to a `fakesink`
(`RK3568_TV_AUDIO_SINK`).
Each script has its test in `scripts/tests/` or `system/tests/`, using stub commands.
