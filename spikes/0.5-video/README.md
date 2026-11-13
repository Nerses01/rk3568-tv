# Step 0.5 video spike: measurement code

Throwaway code that measured the three ways of showing hardware-decoded video in the Qt Quick UI. It is kept so
that the numbers in [docs/03-video-spike.md](../../docs/03-video-spike.md) can be reproduced. It is not product
code: no tests, not built by CI.

| File | What it is |
|---|---|
| `make-clips.sh` | makes the ten test clips from Big Buck Bunny's 2160p60 render with ffmpeg (run on the PC) |
| `spike-play.sh` | GStreamer alone: the decoder at full speed (`decode`), or decoder to a display plane with `kmssink` (`kms`) |
| `videospike/` | Qt Quick app: candidate `a`, `b` or `c` plays one clip under a live QML overlay and prints one result line |
| `egl15-shim.c` | `LD_PRELOAD` shim: gives Ubuntu's Qt Multimedia the EGL 1.5 `eglCreateImage` that the vendor's Mali EGL 1.4 lacks |
| `kms.json`, `kms-argb.json` | Qt EGLFS output configuration: 1920×1080 at 60 Hz; ARGB for candidate C's transparent UI plane |
| `run-all.sh` | every measurement on every clip, into `results-<time>.tsv` |
| `results-2026-11-13.tsv` | the results of the run in docs/03-video-spike.md |

To repeat it on the board (it needs the screen, so stop the desktop first: `systemctl stop gdm`):

```sh
cd /userdata/dev/video-spike             # a copy of this folder
gcc -O2 -shared -fPIC -o libegl15shim.so egl15-shim.c -lEGL
cmake -S videospike -B videospike/build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build videospike/build
sh run-all.sh                            # clips in /userdata/media/test/; about 40 minutes
systemctl start gdm
```

The clips are Big Buck Bunny, (c) copyright 2008 Blender Foundation, www.bigbuckbunny.org, CC BY 3.0.
