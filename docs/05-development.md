# Development (steps 0.7 and 1.1)

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
| `app/src/` | C++: `main.cpp`, and the types QML uses, such as `RemoteKeys` (keys to remote-control actions) |
| `app/qml/` | QML: `Main.qml`, the window |
| `app/tests/` | Qt Test for the C++ (`tst_*.cpp`), Qt Quick Test for the QML (`qml/tst_*.qml`) |

Qt 6.2 needs a few things that later versions don't:
- The module's resources sit under `qrc:/qt/qml`, and the app and the QML tests add that import path themselves.
- A QML file in the module imports the module (`import Rk3568Tv`) to see its C++ types.
- A header with `QML_ELEMENT` or `QML_SINGLETON` includes `<QtQml/qqml.h>`.

## Commands

From the repository's root, or as VS Code tasks (Terminal → Run Task; Ctrl+Shift+B deploys):

| Command | VS Code task | What it does |
|---|---|---|
| `sh scripts/board.sh deploy` | Board: deploy (Ctrl+Shift+B) | copies `app/` to the board, builds it there, restarts it on the screen |
| `sh scripts/board.sh test` | Board: run the tests | copies `app/` to the board, builds everything there and runs the tests, offscreen; the running app stays |
| `sh scripts/board.sh shot [FILE]` | Board: screenshot | the board's screen as a PNG, by default `screenshots/latest.png` (git ignores the folder) |
| `sh scripts/board.sh keys KEY...` | Board: press keys | presses keys on the board, e.g. `keys right right down enter`; `right:1500` holds a key, `wait:500` pauses |
| `sh scripts/board.sh logs [-f]` | Board: follow the log | the app's log from the journal |
| `sh scripts/board.sh stop` | Board: stop the app, desktop back | stops the app and starts GNOME |

Keys: `up`, `down`, `left`, `right`, `enter`, `back`, `home`, `menu`, `esc`, `space`, `playpause`, `volumeup`,
`volumedown` ([scripts/board-keys.c](../scripts/board-keys.c)). VS Code opens the build's error messages at the
right line in the PC's files.

Measured on 2026-11-13 over Wi-Fi:

| | Time |
|---|---|
| First deploy (configures and builds everything) | 41 s |
| Deploy after a QML change | 23 s |
| Deploy with nothing changed (restart only) | 6 s |
| QML change, deployed, keys pressed, screenshot back | 31 s |

## What happens on the board

`deploy` sends `app/` and the board's two scripts to `/userdata/dev/rk3568-tv` as a tar stream. Each file keeps
its time, so the build redoes only what changed. Then [scripts/board-run.sh](../scripts/board-run.sh):

1. Builds with CMake and Ninja in `/userdata/dev/rk3568-tv/build`, and builds the key tool.
2. Stops the running app.
3. Masks the vendor's `hdmi_hotplug.service` until the next reboot. Otherwise every HDMI hotplug would start
   GNOME, which would stop the app (02-board.md, "An HDMI hotplug starts the desktop").
4. Looks at HDMI:
   - If a screen is connected, it saves the screen's EDID.
   - If none is connected (the TV is off), it forces HDMI on with the saved EDID. The app runs as if the screen
     were there, screenshots work, and switching the TV on shows the app.
5. Starts the app as the transient systemd unit `rk3568-tv-dev`:
   - on EGLFS at 1920×1080, 60 Hz (`RK3568_TV_MODE` changes it);
   - as root;
   - with `Conflicts=gdm.service`, so GNOME stops while the app runs.

   If the app doesn't keep running, its log is shown and the deploy fails.

`board.sh shot` reads the screen with ffmpeg's `kmsgrab`: the framebuffer the display shows, whoever drew it.
`board.sh keys` presses keys through a virtual keyboard on `/dev/uinput`. They take the path a real keyboard's
keys take (kernel, udev, libinput, Qt). Each call waits 2 s for libinput to find the keyboard.

`stop` undoes the run-time changes: it returns HDMI to the real screen, unmasks the hotplug service and starts
GNOME. A reboot does the same, since nothing is installed.

## Known rough edges

- **The app runs as root.** Step 1.2 brings the unprivileged user `tv` and the real systemd unit.
- **A stopped app shows as failed.** When systemd stops the app, the app exits with status 1. The journal then
  says "Failed with result 'exit-code'". The unit in step 1.2 has to accept that, or the app has to handle
  SIGTERM itself.
- **Qt warns that `XDG_RUNTIME_DIR` is not set.** It's harmless here; the unit in step 1.2 sets it.
- **The app doesn't run on Windows.** The PC edits, formats and runs CI in Docker; the app itself runs on the
  board.

## Tests, formatting and CI

[scripts/ci.sh](../scripts/ci.sh) holds everything CI checks:
1. the formatting;
2. the app, built with warnings as errors, and its tests;
3. the tests of the shell scripts and the board's tools.

It runs in Ubuntu 22.04, the board's release, so with the same Qt 6.2.4. [scripts/ci-deps.sh](../scripts/ci-deps.sh)
installs the packages it needs.

| Where | How | Takes |
|---|---|---|
| GitHub, every push and pull request | [.github/workflows/ci.yml](../.github/workflows/ci.yml), on GitHub's arm64 runner `ubuntu-22.04-arm` | |
| The PC, before a commit | `sh scripts/in-docker.sh sh scripts/ci.sh` (VS Code task "CI in Docker") | 67 s from scratch, 17 s after |
| The board, the app's tests only | `sh scripts/board.sh test` | 56–74 s |

`scripts/in-docker.sh` builds an Ubuntu 22.04 image with CI's packages on first use, which takes about two
minutes. It builds the image again whenever `ci-deps.sh` changes.

**Formatting:** `sh scripts/format.sh` formats the C++ with clang-format 14, using [.clang-format](../.clang-format)
(Qt-like, 120 columns), and the QML with qmlformat 6.2.4. On Windows, run it as
`sh scripts/in-docker.sh sh scripts/format.sh` (VS Code task "Format"). CI runs `format.sh --check`.
- **No arrow functions in QML:** qmlformat 6.2 turns them into invalid code. Write `function (event) { ... }`.
- **No qmllint:** Qt 6.2's qmllint reports Qt's own `Qt` object as unqualified access.

**Tests:** the app's tests run offscreen with Qt Quick's software renderer, so they need no screen and no GPU.
Each script has its test in `scripts/tests/` or `system/tests/`, using stub commands.
