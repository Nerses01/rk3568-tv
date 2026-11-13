#!/bin/sh
# Step 0.6 UI spike, on the board: the home screen's pictures, cut from the 0.5 test clips with ffmpeg:
# 120 tile posters (720x405, two per second of the 1080p clip) and 20 background stills (3840x2160, one every
# 3 seconds of the 4K clip). Throwaway measurement code.
#
# usage: make-posters.sh [DIR]   (default /userdata/media/posters)
set -eu
src=/userdata/media/test
dst=${1:-/userdata/media/posters}
mkdir -p "$dst"
ffmpeg -v error -y -i "$src/h264-1080p30.mp4" -vf "fps=2,scale=720:405" -frames:v 120 -q:v 4 "$dst/thumb-%03d.jpg"
i=1
while [ "$i" -le 20 ]; do
    ffmpeg -v error -y -ss $((i * 3 - 2)) -i "$src/h264-2160p30.mp4" -frames:v 1 -q:v 3 "$dst/hero-$(printf %02d "$i").jpg"
    i=$((i + 1))
done
echo "$(ls "$dst"/thumb-*.jpg | wc -l) posters, $(ls "$dst"/hero-*.jpg | wc -l) stills in $dst"
