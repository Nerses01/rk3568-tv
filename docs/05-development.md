# Development loop (step 0.7)

The app is edited on the PC, then built and run on the board. One command copies it over, builds it there and
restarts it on the screen; a QML change is on screen in about half a minute. Logs, screenshots and key presses come
back over SSH, so a change can be checked without sitting at the TV, even with the TV switched off.

## Setup

- SSH key login to the board as `root` (02-board.md, "Access").
- A file `.env` in the repository's root, which git ignores: `BOARD=root@<the board's address>`.
- On Windows: Git for Windows, for Git Bash. The scripts are POSIX `sh`.

## Commands

From the repository's root, or as VS Code tasks (Terminal → Run Task; Ctrl+Shift+B deploys):

| Command | VS Code task | What it does |
|---|---|---|
| `sh scripts/board.sh deploy` | Board: deploy (Ctrl+Shift+B) | copies `app/` to the board, builds it there, restarts it on the screen |
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
- **The app can't run from Windows.** The PC only edits; Qt, the build and the app run on the board. Step 1.1 adds
  a build on GitHub Actions for the tests.

## Tests of the scripts

```sh
sh scripts/tests/test-board.sh        # board.sh, with a stub ssh: on the PC or the board
sh scripts/tests/test-board-run.sh    # board-run.sh, with stub cmake, systemctl, sysfs: on the PC or the board
sh scripts/tests/test-board-keys.sh   # board-keys.c in a dry run: needs gcc, so on the board
```
