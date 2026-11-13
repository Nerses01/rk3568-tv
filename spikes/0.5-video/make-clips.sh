#!/bin/bash
# Step 0.5: make the test clips from Big Buck Bunny (c) Blender Foundation, CC-BY 3.0 (peach.blender.org).
# Every clip is the same 60 s (from 2:00) of the 2160p60 H.264 render, so codecs and sizes compare directly.
# usage: make-clips.sh FFMPEG_DIR SOURCE_MP4 OUT_DIR
set -u
bin=$1 src=$2 out=$3
ff() { "$bin/ffmpeg.exe" -hide_banner -loglevel error -nostdin -y "$@"; }
mkdir -p "$out"
log=$out/make-clips.log
seg=(-ss 120 -t 60 -i "$src")
aac=(-c:a aac -b:a 128k -ac 2)
opus=(-c:a libopus -b:a 128k -ac 2)
run() {   # NAME ARGS...: encode one clip, log its time
    name=$1; shift
    [ -s "$out/$name" ] && { echo "skip $name (exists)" >> "$log"; return; }
    start=$(date +%s)
    if ff "$@" "$out/$name.part.${name##*.}"; then
        mv "$out/$name.part.${name##*.}" "$out/$name"
        echo "$(date '+%T') $name: $(( $(date +%s) - start )) s, $(stat -c %s "$out/$name") bytes" >> "$log"
    else
        echo "$(date '+%T') $name: FAILED" >> "$log"
    fi
}
echo "$(date '+%F %T') start" >> "$log"
# H.264: the original 2160p60 stream as it is, plus 2160p30 and 1080p30 with x264
run h264-2160p60.mp4 "${seg[@]}" -map 0:v:0 -map 0:a:0 -c:v copy "${aac[@]}" -movflags +faststart
run h264-2160p30.mp4 "${seg[@]}" -map 0:v:0 -map 0:a:0 -vf fps=30 -c:v libx264 -preset medium -crf 20 -profile:v high -level 5.1 -pix_fmt yuv420p "${aac[@]}" -movflags +faststart
run h264-1080p30.mp4 "${seg[@]}" -map 0:v:0 -map 0:a:0 -vf scale=1920:1080:flags=lanczos,fps=30 -c:v libx264 -preset medium -crf 20 -profile:v high -level 4.1 -pix_fmt yuv420p "${aac[@]}" -movflags +faststart
# H.265 (x265), 8-bit, and one 10-bit 2160p60
x265=(-c:v libx265 -preset faster -crf 22 -tag:v hvc1 -x265-params log-level=error)
run h265-1080p30.mp4 "${seg[@]}" -map 0:v:0 -map 0:a:0 -vf scale=1920:1080:flags=lanczos,fps=30 "${x265[@]}" -pix_fmt yuv420p "${aac[@]}" -movflags +faststart
run h265-2160p30.mp4 "${seg[@]}" -map 0:v:0 -map 0:a:0 -vf fps=30 "${x265[@]}" -pix_fmt yuv420p "${aac[@]}" -movflags +faststart
run h265-2160p60.mp4 "${seg[@]}" -map 0:v:0 -map 0:a:0 "${x265[@]}" -pix_fmt yuv420p "${aac[@]}" -movflags +faststart
run h265-10bit-2160p60.mp4 "${seg[@]}" -map 0:v:0 -map 0:a:0 "${x265[@]}" -pix_fmt yuv420p10le -profile:v main10 "${aac[@]}" -movflags +faststart
# VP9 (libvpx), profile 0
vp9=(-c:v libvpx-vp9 -crf 31 -b:v 0 -deadline good -cpu-used 5 -row-mt 1 -tile-columns 2 -threads 12)
run vp9-1080p30.webm "${seg[@]}" -map 0:v:0 -map 0:a:0 -vf scale=1920:1080:flags=lanczos,fps=30 "${vp9[@]}" -pix_fmt yuv420p "${opus[@]}"
run vp9-2160p30.webm "${seg[@]}" -map 0:v:0 -map 0:a:0 -vf fps=30 "${vp9[@]}" -pix_fmt yuv420p "${opus[@]}"
run vp9-2160p60.webm "${seg[@]}" -map 0:v:0 -map 0:a:0 "${vp9[@]}" -pix_fmt yuv420p "${opus[@]}"
echo "$(date '+%F %T') done" >> "$log"
