# Step 0.6 UI spike: measurement code

Throwaway code that measured whether a Qt Quick TV home screen holds 60 fps on EGLFS with the Mali driver, at
1080p and 4K output, driven from a keyboard with no desktop running. It is kept so that the numbers in
[docs/04-ui-spike.md](../../docs/04-ui-spike.md) can be reproduced. It is not product code: no tests, not built by CI.

| File | What it is |
|---|---|
| `uispike/` | Qt Quick app: a home screen (rows of poster tiles, a background still that cross-fades, a pulsing focus frame); prints one result line when Esc is pressed |
| `keys.c` | a virtual keyboard through `/dev/uinput`: plays a key script through the same path as a real keyboard (kernel, udev, libinput, Qt) |
| `make-posters.sh` | cuts the home screen's pictures from the 0.5 test clips with ffmpeg, into `/userdata/media/posters` |
| `run-all.sh` | a minute of scripted browsing at each output setting, into `results-<time>.tsv`; give a 4K mode to add the runs for a 4K screen |
| `results-2026-11-13.tsv` | the results of the run in docs/04-ui-spike.md |

To repeat it on the board (the clips from step 0.5 must be in `/userdata/media/test/`):

```sh
cd /userdata/dev/ui-spike                # a copy of this folder
gcc -O2 -o keys keys.c
cmake -S uispike -B uispike/build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build uispike/build
sh make-posters.sh                       # about 2 minutes
sh run-all.sh                            # stops the desktop, about 9 minutes, starts it again
```

To try it with a real keyboard, stop the desktop and start the app by hand; Esc ends it:

```sh
systemctl stop gdm
QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms uispike/build/uispike try preferred
systemctl start gdm
```

The pictures are cut from Big Buck Bunny, (c) copyright 2008 Blender Foundation, www.bigbuckbunny.org, CC BY 3.0.
