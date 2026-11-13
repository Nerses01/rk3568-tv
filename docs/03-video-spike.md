# Video spike (step 0.5)

**Question:** how should hardware-decoded video be shown inside the Qt Quick UI (01-plan.md, §4.3)?

**Answer: candidate B.** Our own GStreamer pipeline ends in `appsink`. The decoder's DMA-BUF frames are imported as
EGLImages and drawn by the GPU inside Qt Quick's render pass, under the QML scene. Measured on 2026-11-13:
- every frame is shown at 1080p30 and 4K30, H.264 and H.265 alike;
- the UI keeps 60 fps;
- about 55 % of one CPU core;
- no frame is copied.

## How it was measured

- **Setup:** the board as in [02-board.md](02-board.md), with the desktop stopped. Qt 6.2.4 on EGLFS (`eglfs_kms`) at
  1920×1080, 60 Hz, on a 2560×1440 monitor. Qt Quick renders with OpenGL ES 3.2 on the Mali-G52.
- **Clips:** 60 seconds of Big Buck Bunny (Blender Foundation, CC BY 3.0) from 2:00, all made from its 2160p60 H.264
  render:

  | Clip | Size | Clip | Size |
  |---|---|---|---|
  | H.264 1080p30 (x264) | 27 MB | H.265 1080p30 (x265) | 17 MB |
  | H.264 2160p30 (x264) | 75 MB | H.265 2160p30 | 43 MB |
  | H.264 2160p60 (Blender's own stream, level 5.1) | 52 MB | H.265 2160p60 | 45 MB |
  | VP9 1080p30, 2160p30, 2160p60 (libvpx) | 16, 38, 59 MB | H.265 2160p60 10-bit | 44 MB |

- **Live UI on top:** in every candidate a caption and a rotating, translucent square are drawn over the video, so
  Qt Quick redraws every frame. That is the worst case for a TV UI.
- **Frames shown:** counted exactly: in the app for A and B, at the sink for C and `kmssink`. Dropped = the clip's
  frames minus the frames shown.
- **UI fps:** frames Qt presented, per second.
- **CPU:** the process as a percentage of one core (four cores make 400 %), and the whole system as a percentage of
  all four.

The code and the raw results are in [spikes/0.5-video/](../spikes/0.5-video/).

## Results

Frames shown out of the clip's frames; UI fps; process CPU.

| Clip | Decoder alone, as fast as it can | `kmssink` alone (no UI) | **B** | A (Qt Multimedia) | C (`kmssink` under Qt) |
|---|---|---|---|---|---|
| H.264 1080p30 | 247 fps | 1800/1800, 32 % | **1799/1800, UI 60, 58 %** | 1784/1800, UI 19, 94 % | 1495/1800, UI 25, 50 % |
| H.264 2160p30 | 65 fps | 1794/1800, 59 % | **1799/1800, UI 60, 54 %** | | |
| H.264 2160p60 | 58 fps, and loses 291 frames | 80/3779 | 63/3779, UI 60 | | |
| H.265 1080p30 | 414 fps | 1800/1800, 36 % | **1800/1800, UI 60, 55 %** | | |
| H.265 2160p30 | 99 fps | 1800/1800, 66 % | **1799/1800, UI 60, 55 %** | 655/1800, UI 6, 98 % | 1116/1800, UI 30, 66 % |
| H.265 2160p60 | 100 fps | 3417/3600, 78 % | not measured | | |

The run was stopped after these six clips. The SoC stayed between 54 and 59 °C.

What the developer saw on the screen:
- **B:** smooth everywhere except H.264 2160p60. There the video froze while the UI kept moving smoothly.
- **A:** small stutters at 1080p and freezes at 4K.
- **C:** looked fine at 1080p and showed small freezes at 4K.

## Why B

- **B** shows every frame up to 4K30 with the UI at 60 fps. The GPU samples the decoder's own NV12 buffers, so no
  frame is copied.
- **A**, Qt Multimedia 6.2, copies every frame through the CPU. The UI drops to 19 fps at 1080p and 6 fps at 4K.
  Ubuntu's Qt Multimedia also doesn't load with the vendor's Mali EGL without a shim (finding 1 below).
- **C** in its simple form has `kmssink` drive a plane through Qt's DRM device. Qt's page flips and `kmssink`'s plane
  updates then each wait for the screen, so the UI runs at about 30 fps and video frames are lost. Done properly, C
  would put both planes into one atomic commit. Qt 6.2 doesn't expose its commit, so that means writing our own
  compositor. B is good enough that C isn't needed. C stays an option if 4K60 or power use ever call for it:
  `kmssink` alone showed 4K30 with no GPU work at all.

## What the spike taught us about the platform

1. **Mali EGL is version 1.4.** The vendor's `/usr/lib/aarch64-linux-gnu/mali/libEGL.so.1` is found before Ubuntu's
   (`/etc/ld.so.conf.d/00-aarch64-mali.conf`). Ubuntu's Qt Multimedia calls the EGL 1.5 functions `eglCreateImage` and
   `eglDestroyImage`, and fails to load ("undefined symbol"). The product therefore doesn't use Qt Multimedia for
   video.
2. **Ubuntu's Qt 6 is built for desktop OpenGL**, yet Qt Quick runs with OpenGL ES 3.2 on EGLFS, because Qt looks up
   GL functions through EGL. Our own GL calls must go through `QOpenGLContext::extraFunctions()`. A plain `gl*` call
   lands in glvnd's `libOpenGL`, which has no context, and silently does nothing.
3. **EGL on GBM** has to be opened with `eglGetPlatformDisplayEXT(EGL_PLATFORM_GBM_KHR, …)`; plain `eglGetDisplay`
   fails. It offers `EGL_EXT_image_dma_buf_import` (with modifiers), fences and surfaceless contexts.
4. **GStreamer is the vendor's 1.22.9**, with its own development headers and `pkg-config` files (app, video,
   allocators, gl). Ubuntu's `libgstreamer-plugins-base1.0-dev` conflicts with the held packages and isn't needed.
5. **`mppvideodec`** ranks above the software decoders and outputs NV12 in DMA-BUFs. The same buffer can come with a
   different file descriptor each time, and a closed descriptor's number is reused. So buffers must be identified by
   their inode (`fstat`), not by descriptor number. The first B version keyed on the number and showed old frames.
6. **A `queue` belongs between the decoder and the sink.** Without it, decoding and display share one thread. At 4K
   the frames then arrive late, and the sink's QoS makes the decoder drop them. H.265 2160p30 in a 20-second test:
   456 of 602 frames without the queue, 602 of 602 with it.
7. **Display planes:**
   - Left to itself, `kmssink` picks `Smart1`, which shows only RGB. The decoder then ends without a frame and without
     an error.
   - `Esmart0` (id 121) and `Esmart1` (id 107) show NV12.
   - With `kmssink`, `skip-vsync=true` is needed. Otherwise it waits for the screen twice per frame and drops frames.
8. **H.264 at 2160p60 is beyond the chip**: the decoder alone reaches 58 fps and loses frames. H.265 manages 2160p at
   100 fps. For 4K60, H.265 or VP9 sources are needed.
9. **Inside the GNOME desktop, video plays badly:**
   - `xvimagesink`: 18 fps for 1080p30;
   - `rkximagesink` and `glimagesink`: don't work;
   - Qt under X: finds no EGL configuration with this driver.
10. **On EGLFS the Qt Quick UI holds 60 fps at 1920×1080** while video plays. That is also a first answer for step 0.6.

## In the product (step 1.4)

The app's player (`app/src/videoplayer.cpp`) uses candidate B, with three changes:

- **Pipeline:** GStreamer's `playbin` replaces the hand-made pipeline. It still picks `mppvideodec`, and the decoder's
  DMA-BUFs reach the player unchanged.
- **10-bit:** the decoder outputs `NV12_10LE40` (DRM's NV15), and the Mali GPU imports NV15 directly. Forcing NV12
  from the decoder instead makes its RGA conversion fail ("Error srcRect").
- **Frames go back late enough.** At 4K60 the GPU runs frames behind its commands. Handing a frame back to the decoder
  two frames after showing it tore the picture: the decoder was writing a buffer the GPU was still reading. Each draw
  now ends with an EGL fence, and a frame goes back only once its fence has signalled.

Measured on 2026-11-13, through the app, 10–20 s per clip. Frames counted as they reached the player; every one was a
DMA-BUF:

| Clip | Frames per second |
|---|---|
| H.264 1080p30, 2160p30 | 30 |
| H.264 2160p60 | about 22: beyond the chip (finding 8) |
| H.265 1080p30, 2160p30 | 30 |
| H.265 2160p60 | 60 |
| H.265 10-bit 2160p60 | 60 |
| VP9 1080p30, 2160p30 | 30 |
| VP9 2160p60 | 60 |

With the TV off, the whole system used about 20 % of the CPU for H.264 1080p30.

## Not measured yet

- **4K output:** the monitor stops at 2560×1440, and everything ran at 1920×1080. To be tested on a 4K monitor.
- **Sound and audio/video sync, by ear.** The sound goes to HDMI, but the TV was off.
- **HDR:** 10-bit video shows correctly, but HDR10 content isn't tone-mapped to the 8-bit picture.
- **Long runs and their temperature.**
