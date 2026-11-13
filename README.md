# rk3568-tv

A smart-TV interface for a Rockchip RK3568 board running Ubuntu 22.04. The board boots straight into a
full-screen home screen, is driven with a remote or a keyboard, and plays video up to 4K with the chip's
hardware decoder.

**Status:** Phase 0, groundwork on the board; nothing to install yet. The plan is in
[docs/01-plan.md](docs/01-plan.md).

## Hardware

Developed on a GZPEITE RK3568 P01 board (4× Cortex-A55, Mali-G52 GPU, 4 GB RAM, 16 GB eMMC) with the vendor's
Ubuntu 22.04 image and Rockchip's 5.10 kernel. Other RK3566 and RK3568 boards with a Rockchip Ubuntu image
may work with small changes; that is not a goal of the first version.

## What it is meant to do

- Planned: local files and USB drives, IPTV playlists, Jellyfin, YouTube; H.264, H.265 and VP9 up to 4K
  decoded in hardware; control by keyboard, by the TV's own remote (HDMI-CEC), by an IR remote or by a phone.
- Not possible: Netflix, Disney+, Prime Video and other services that require a certified device with hardware
  DRM (Widevine L1).

## Documentation

| Doc | Contents |
|---|---|
| [docs/01-plan.md](docs/01-plan.md) | goals, scope, technical approach, phases and steps, risks, decisions |
| [docs/02-board.md](docs/02-board.md) | the board: hardware, partitions, access, our changes, backup and restore, known faults and their fixes |
| [docs/03-video-spike.md](docs/03-video-spike.md) | step 0.5: how hardware-decoded video gets into the UI, with measurements |
