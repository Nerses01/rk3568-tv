#!/bin/sh
# Step 0.5: every measurement on every test clip, one result line each, into results-<time>.tsv.
# Run with the display manager stopped (EGLFS and kmssink need the screen). Throwaway measurement code.
set -u
cd "$(dirname "$0")" || exit 1
out=$PWD/results-$(date +%Y%m%d-%H%M).tsv
printf "test\tclip\tframes\tshown\tdropped\tvideo_fps\tui_fps\tproc_cpu%%\tsys_cpu%%\tsoc_C\n" > "$out"
export QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms LD_PRELOAD=$PWD/libegl15shim.so
pause() { sleep 15; }   # let the SoC cool a little between runs

qt() {   # CANDIDATE CLIP FRAMES CONFIG
    QT_QPA_EGLFS_KMS_CONFIG=$PWD/$4 timeout -s KILL 200 videospike/build/videospike "$1" "$2" "$3" 2>> errors.log |
        grep -v arm_release >> "$out" || printf "%s\t%s\t%s\tFAILED\n" "$1" "$(basename "$2")" "$3" >> "$out"
}

[ "$#" -gt 0 ] || set -- /userdata/media/test/h264-1080p30.mp4 /userdata/media/test/h264-2160p30.mp4 \
    /userdata/media/test/h264-2160p60.mp4 /userdata/media/test/h265-1080p30.mp4 \
    /userdata/media/test/h265-2160p30.mp4 /userdata/media/test/h265-2160p60.mp4 \
    /userdata/media/test/h265-10bit-2160p60.mp4 /userdata/media/test/vp9-1080p30.webm \
    /userdata/media/test/vp9-2160p30.webm /userdata/media/test/vp9-2160p60.webm
for clip in "$@"; do
    [ -f "$clip" ] || { printf "-\t%s\tMISSING\n" "$(basename "$clip")" >> "$out"; continue; }
    frames=$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$clip")
    echo "$(date +%T) $(basename "$clip") ($frames frames)" >> progress.log
    sh spike-play.sh decode "$clip" >> "$out" 2>> errors.log; pause
    sh spike-play.sh kms "$clip" >> "$out" 2>> errors.log; pause
    qt b "$clip" "$frames" kms.json; pause
    case $(basename "$clip") in
    h264-1080p30.mp4 | h265-2160p30.mp4 | h265-2160p60.mp4)
        qt a "$clip" "$frames" kms.json; pause
        qt c "$clip" "$frames" kms-argb.json; pause
        ;;
    esac
done
echo "$(date +%T) done: $out" >> progress.log
