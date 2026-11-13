# CLAUDE.md

Guidance for Claude Code sessions in this repository.

## What this is

rk3568-tv: a smart-TV app for a Rockchip RK3568 board (GZPEITE RK3568 P01) running the vendor's Ubuntu 22.04.
The board boots into a full-screen Qt Quick home screen and plays video with the chip's hardware decoder. The
docs are the source of truth; read them before changing anything:

| Doc | Use it for |
|---|---|
| `docs/01-plan.md` | goals, scope, technical approach, phases and steps, risks, open questions, decisions log |
| `docs/02-board.md` | the board: hardware, partitions, access, our changes, backup and restore, known faults and their fixes |
| `docs/03-video-spike.md` | how video gets into the Qt Quick UI (candidate B), its numbers, and what the platform needs for it |
| `docs/04-ui-spike.md` | the UI on EGLFS without a desktop: 1080p at 60 fps, 4K by scaling, keyboard input, and what the platform needs for it |
| `docs/05-development.md` | the app's code layout; deploy, logs, screenshots and keys with `scripts/board.sh`; tests, formatting and CI |

`CLAUDE.local.md` (git-ignored) holds the board's network address and how to log in. Read it before touching
the board; if it is missing, ask the developer.

## Working agreement

- One plan step at a time. Each step ends with its "done when" met and one commit by Claude, in Conventional
  Commits style (`feat:`, `fix:`, `docs:`, `chore:`, `test:`, `ci:`), with the attribution trailer.
- Claude never pushes and never rewrites history unless the developer asks for it in that conversation.
- Work on `main`, one commit per step. CI exists since step 1.1, and its checks run in Docker before each commit, so
  `main` stays green (decided 2026-11-13).
- New code comes with tests.
- Significant technical choices get a row in the decisions log (`docs/01-plan.md` §8).
- English everywhere in the repository.
- **The repository is public.** Never commit the board's IP, MAC or Bluetooth addresses, passwords, keys or
  tokens. They belong in `CLAUDE.local.md` or a git-ignored `.env`.

## Working on the board

The board is the only test machine, and SSH is the only way in when nobody is at the TV.

- Log in with `ssh root@<board>`; key login works from the developer's PC.
- Run the app with `scripts/board.sh deploy`, and check it with `scripts/board.sh shot` (then read
  `screenshots/latest.png`) and `scripts/board.sh keys`. The developer prefers not to sit at the TV, and the TV may
  be off (docs/05-development.md).
- Never flash the board or change the bootloader, the partitions or the boot partition without the developer's
  go-ahead in that conversation, and never before the backup from step 0.2 exists.
- Never cut off the way in: no changes to networking, sshd or a firewall without a tested way back.
- Keep GNOME installed until Phase 1 is done; it is the way back if the TV app fails at boot.
- The vendor's Rockchip packages (MPP, libmali, RGA and the patched GStreamer and libdrm) are held by apt.
  Never upgrade, unhold or replace them.
- `/` is small (about 2 GB free): build trees, test media and downloads go to `/userdata`.
- Never switch Bluetooth off (rfkill) on the board; the chip then loses its firmware. Recovery is in
  `docs/02-board.md`.

## Conventions

- C++20, Qt 6.2.4 from Ubuntu's apt (unless a spike changes it), CMake and Ninja.
- Scripts that run on the board are POSIX `sh` with LF line endings; `.gitattributes` enforces LF.
- clang-format 14 for C++ (`.clang-format`) and qmlformat 6.2.4 for QML: `sh scripts/format.sh`, on Windows inside
  `sh scripts/in-docker.sh`. No arrow functions in QML; qmlformat 6.2 corrupts them.
- Before each commit, run what CI runs: `sh scripts/in-docker.sh sh scripts/ci.sh`. It must pass. The app's tests
  also run on the board with `sh scripts/board.sh test`.
