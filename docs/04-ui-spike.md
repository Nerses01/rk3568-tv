# UI spike (step 0.6)

**Question:** can the Qt Quick home screen run full-screen on EGLFS with the Mali driver, with no desktop, at 60 fps
for 1080p and 4K output, driven from a keyboard (01-plan.md, §4.2)?

**Answer: yes at 1080p. For 4K, the UI is drawn at 1080p and the display controller scales it up.** Measured on
2026-11-13 with Qt 6.2.4 on EGLFS (`eglfs_kms`) and GNOME stopped:
- At 1920×1080 and 60 Hz, the home screen holds 59.4 fps while browsing. About 1 % of frames are late, nearly all
  of them when a full-screen background picture is uploaded to the GPU.
- The GPU can't draw the same screen at 3840×2160 within one refresh. It manages 28 fps, and 44 fps with no
  pictures at all. A 1080p framebuffer scaled by the display controller costs the GPU nothing.
- Keys arrive through libinput, from the real USB keyboard and from a keyboard plugged in while the app runs.
- No X11 fallback is needed.

## How it was measured

- **Setup:** the board as in [02-board.md](02-board.md), with the desktop stopped (`systemctl stop gdm`). Qt Quick
  uses its threaded render loop and OpenGL ES 3.2 on the Mali-G52.
- **The screen:** a Sharp TV from 2013, 1080p at most. According to its EDID it prefers 1280×720 at 50 Hz, its
  pixel clock tops out at 150 MHz, and it has HDMI-CEC. No 4K screen was at hand.
- **The home screen** is laid out at 1920×1080 and scaled to the framebuffer:
  - A title, a synopsis and a clock sit over a full-screen still of the focused title, darkened by two
    full-screen gradients.
  - Below them are 8 rows of 100 poster tiles. The posters are 720×405 JPEG files, decoded at the size they're
    shown.
  - The focused tile grows by 12 % and its frame pulses, so every refresh draws a new frame. That is the worst
    case for a TV UI, and it makes frame times measurable.
  - When the focus rests for 0.4 s, the focused title's still (3840×2160 JPEG, decoded at the framebuffer's size)
    cross-fades in.
  - The pictures are cut from the 0.5 test clips (Big Buck Bunny).
- **Browsing:** in every run, a virtual keyboard on `/dev/uinput` plays the same 58-second script. It steps along a
  row, rests, holds a key so that Qt repeats it, and changes rows: 102 presses and about 115 repeats. The device
  appears 4 s after the app starts, so every run also tests a keyboard plugged in while the app runs.
- **Frame times:** the time of every `frameSwapped`, which on `eglfs_kms` comes after the page flip. A late frame
  (jank) is a gap longer than 1.5 refreshes (25 ms at 60 Hz): the screen showed the previous frame again.
- **4K without a 4K screen:** the 1080p mode gets a 3840×2160 framebuffer, set with `"size"` in Qt's KMS
  configuration (this needs atomic modesetting). The display controller scales it down, and the GPU draws exactly
  what it would draw for a 4K screen.
- **CPU:** the process as a percentage of one core. **GPU:** Mali's utilisation and clock, read on a thread of their
  own (finding 2).

The code and the raw results are in [spikes/0.6-ui/](../spikes/0.6-ui/).

## Results

58 seconds of browsing per run, the last 55 of them measured
([results-2026-11-13.tsv](../spikes/0.6-ui/results-2026-11-13.tsv)):

| Run | Framebuffer | fps | Median frame | Late frames | Worst frame | Process CPU | GPU | Memory |
|---|---|---|---|---|---|---|---|---|
| **1080p** | 1920×1080 | **59.4** | 16.7 ms | 38 of 3272 | 47.5 ms | 61 % | 35 % at 704 MHz | 159 MB |
| 1080p, atomic modesetting | 1920×1080 | 59.4 | 16.7 ms | 43 | 53.6 ms | 62 % | 35 % at 701 MHz | 161 MB |
| 1080p, no background stills | 1920×1080 | 59.8 | 16.7 ms | 8 | 29.8 ms | 61 % | 34 % at 425 MHz | 132 MB |
| 1080p, no pictures at all | 1920×1080 | 59.9 | 16.7 ms | 1 | 26.3 ms | 50 % | 34 % at 402 MHz | 90 MB |
| 4K framebuffer | 3840×2160 | 27.9 | 33.5 ms | 1535 | 133 ms | 54 % | 58 % at 797 MHz | 349 MB |
| 4K framebuffer, memory clock at its highest | 3840×2160 | 27.8 | 33.4 ms | 1528 | 153 ms | 54 % | 58 % at 797 MHz | 350 MB |
| 4K framebuffer, no pictures | 3840×2160 | 44.4 | 18.7 ms | 858 | 36.2 ms | 39 % | 52 % at 800 MHz | 93 MB |

- **Repeat:** an earlier run of the first four gave the same picture: 59.3 and 59.4 fps with 42 and 36 late frames
  at 1080p, and 28.0 and 27.8 fps for the 4K framebuffer.
- **System:** 10–17 % CPU across all four cores. The SoC stayed between 43 and 47 °C.
- **Keys:** every run received all 102 presses.
- **Startup:** the first frame came 0.8–1.0 s after the process started.

With the real USB keyboard (a Chicony keyboard in the upper USB 3.0 port), the developer browsed for 112 s at 1080p.
All 39 presses and 55 repeats arrived; the UI ran at 59.9 fps with 7 late frames.

## Why this choice

- **EGLFS works.** Qt Quick draws straight to the screen with the Mali driver at 60 fps, with no desktop and no
  compositor. The X11 fallback isn't needed. It wasn't a ready fallback anyway: Qt under X finds no EGL
  configuration with this driver ([03-video-spike.md](03-video-spike.md), finding 9).
- **The UI is drawn at 1080p.**
  - At 4K the GPU needs just over one refresh per frame. It runs at its top clock, and a faster memory clock
    changes nothing, so the GPU itself is the limit. Even with no pictures, 4K reaches only 44 fps.
  - On a 4K screen, the app gives Qt a 1920×1080 framebuffer and the display controller scales it to the screen.
    That costs the GPU nothing, and the plane's scaler works with Qt's atomic modesetting (here it scaled
    3840×2160 down to 1080p).
- **Atomic modesetting** makes no difference at 1080p. It's needed only for a framebuffer whose size differs from
  the screen's.
- **Late frames come from the pictures.** Nearly all come from the full-screen stills: each one is about 8 MB that the
  render thread uploads to the GPU the moment it appears. Without stills, 8 frames in 55 s were late; without any
  picture, 1. Step 1.3 keeps background stills well below the screen's size and loads the next one ahead.

## What the spike taught us about the platform

1. **Qt's KMS libraries load Mesa's GBM.** `libQt6EglFsKmsGbmSupport.so.6` has RUNPATH `$ORIGIN`, so the loader
   finds Mesa's `libgbm.so.1` in Qt's own folder before the Mali one, even though `ld.so.cache` lists the Mali
   folder first. Qt then stops with "Could not create GBM device".
   - **Fix:** the executable itself needs `libEGL.so.1`, `libGLESv2.so.2` and `libgbm.so.1`, ahead of the Qt
     libraries. A library already loaded under a soname is the one Qt then gets.
   - The app calls none of these libraries, so the linker drops them unless they're linked with `--no-as-needed`,
     as plain `-l` items. CMake merges and moves full library paths (see
     [CMakeLists.txt](../spikes/0.6-ui/uispike/CMakeLists.txt)).
   - The 0.5 app worked only because it calls EGL itself.
2. **Mali's `utilisation` file takes 100 ms to read.** `/sys/devices/platform/fde60000.gpu/utilisation` measures for
   its period (`utilisation_period`, 100 ms) before it answers. The first version read it every 100 ms on the GUI
   thread, and the UI ran at 10 fps. Read it only on a thread of its own; devfreq's `cur_freq` and `load` answer at
   once.
3. **The TV's preferred mode is 1280×720 at 50 Hz**, so Qt's default, the preferred mode, would give 720p50.
   - The app sets the mode itself: 1920×1080 at 60 Hz in Qt's KMS configuration.
   - The settings screen (step 1.6) lets the viewer choose another.
   - This TV also offers 1080p at 50 Hz and 24 Hz.
4. **libinput is Qt's input on EGLFS**, and it opens every device udev tags as a keyboard:
   - the USB keyboard;
   - `hdmi_cec_key`, the TV's remote over HDMI-CEC;
   - `fe6e0030.pwm`, the IR receiver;
   - the power key and `adc-keys`.

   The remotes may therefore arrive as keys without extra code (step 1.7). A keyboard that appears while the app
   runs is picked up, and Qt repeats a held key itself.
5. **The GPU clock follows the load** (`simple_ondemand`): 200 MHz at rest, 400–800 MHz while browsing.
6. **Memory:** the process takes 159 MB at 1080p and 349 MB with a 4K framebuffer. The board has 4 GB.

## Not measured yet

- **A real 4K screen:** its 4K modes, and a 1080p framebuffer scaled up. This spike showed only the scaler working
  downwards.
- **Video on a 4K screen.** Candidate B draws video inside the UI's framebuffer, so with a 1080p framebuffer, 4K
  video would show at 1080p. The player (step 1.4) then needs a 4K framebuffer while playing, when only the video
  and a light overlay change, or video on its own plane (candidate C).
- **Rounded poster corners, shadows and blur.** In Qt 6.2 each needs an offscreen layer per item and costs GPU time.
- **Long runs and temperature**, and running as the unprivileged user `tv` (step 1.2). It will need access to
  `/dev/dri/card0` and `/dev/input/*`.
