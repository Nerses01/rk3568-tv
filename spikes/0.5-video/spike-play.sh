#!/bin/sh
# Step 0.5 video spike, on the board: play test clips with the hardware decoder (mppvideodec) and print one
# measurement line per run. Throwaway measurement code.
#
# usage: spike-play.sh MODE CLIP...
#   MODE decode  as fast as possible into fakesink: the decoder's own speed
#        kms     to the screen with kmssink, in real time (needs the display manager stopped)
#        x11     to the screen with xvimagesink in the X session, in real time
# Frames are counted exactly: ffprobe counts the clip's video packets, an identity element before the sink
# counts the frames that reach it, and the sink's QoS messages count the ones it dropped as late.
# Output (tab-separated): clip mode shown dropped shown_fps wall_s proc_cpu% sys_cpu% soc_C
set -u
mode=$1
shift

cpu() { awk '/^cpu / { print $2 + $3 + $4 + $5 + $6 + $7 + $8, $5 + $6 }' /proc/stat; }   # total idle
temp() { echo $(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000)); }

case $mode in
decode) sink="fakesink name=out sync=false" ;;
kms) sink="queue max-size-buffers=4 ! kmssink name=out plane-id=121 skip-vsync=true" ;;   # Esmart0 shows NV12; skip-vsync avoids a double wait; the queue lets decoding and display run in parallel
x11)
    sink="xvimagesink name=out"
    export DISPLAY=:0 XAUTHORITY=/run/user/0/gdm/Xauthority
    ;;
*) echo "usage: spike-play.sh decode|kms|x11 CLIP..." >&2; exit 1 ;;
esac

for clip in "$@"; do
    case $clip in
    *.webm) src="matroskademux name=d d.video_0 ! queue ! vp9parse" ;;
    *h264*) src="qtdemux name=d d.video_0 ! queue ! h264parse" ;;
    *h265*) src="qtdemux name=d d.video_0 ! queue ! h265parse" ;;
    *) echo "$clip: unknown codec" >&2; continue ;;
    esac
    log=/dev/shm/spike-play.log
    set -- $(cpu)
    t0=$1 i0=$2
    s0=$(date +%s.%N)
    # a fresh shell, so that `times` reports gst-launch's CPU time alone
    ct=$(sh -c "gst-launch-1.0 -v -m filesrc location='$clip' ! $src ! mppvideodec ! identity name=count silent=false ! $sink > $log 2>&1; times" | tail -1)
    s1=$(date +%s.%N)
    set -- $(cpu)
    t1=$1 i1=$2
    # frames in the clip; frames that reached the sink; of those, frames the sink itself dropped as late.
    # Frames the decoder skipped (QoS from the sink) never reach the sink, so: shown = reached - sink_dropped.
    total=$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$clip")
    reached=$(grep -c 'count: last-message = chain' "$log")
    late=$(grep 'message: qos' "$log" | grep 'element "out"' | sed -n 's/.*dropped=(guint64)\([0-9]*\).*/\1/p' | sort -n | tail -1)
    frames=$((reached - ${late:-0}))
    dropped=$((total - frames))
    grep -qE "^ERROR|not-negotiated|Could not" "$log" && echo "$(basename "$clip") $mode: $(grep -m1 -E '^ERROR|not-negotiated|Could not' "$log")" >&2
    # same columns as videospike: test clip frames shown dropped video_fps ui_fps proc_cpu% sys_cpu% soc_C
    echo "$ct $s0 $s1 $t0 $t1 $i0 $i1" | awk -v c="$(basename "$clip")" -v m="gst-$mode" -v t="$total" \
        -v f="$frames" -v d="$dropped" -v soc="$(temp)" '
        # fields: 1 user, 2 sys (from times), 3 start, 4 end, 5 6 total jiffies, 7 8 idle jiffies
        function sec(x) { split(x, p, "m"); sub("s", "", p[2]); return p[1] * 60 + p[2] }
        { wall = $4 - $3; proc = sec($1) + sec($2)
          printf "%s\t%s\t%s\t%s\t%s\t%.1f\t-\t%.0f\t%.0f\t%s\n", m, c, t, f, d, f / wall,
                 100 * proc / wall, 100 * (($6 - $5) - ($8 - $7)) / ($6 - $5), soc }'
done
