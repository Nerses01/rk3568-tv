#!/bin/sh
# Step 0.6 UI spike, on the board: the home screen under a minute of scripted browsing at each output setting, one
# result line each (see uispike/main.cpp), into results-<time>.tsv. Stops the desktop for the runs and starts it
# again at the end. Throwaway measurement code.
#
# usage: run-all.sh [MODE_4K]
# On a 1080p screen: 1080p, and a 3840x2160 framebuffer that the display scales down to 1080p, which gives the GPU
# the work of a 4K screen (once more with the memory clock at its highest). With MODE_4K, for a 4K screen (for
# example 3840x2160@60): also 4K output, and a 1080p framebuffer that the display scales up to 4K.
set -u
cd "$(dirname "$0")" || exit 1
mode4k=${1:-}
out=$PWD/results-$(date +%Y%m%d-%H%M).tsv
printf "test\tframebuffer\tmode\thz\tseconds\tframes\tfps\tp50_ms\tp99_ms\tmax_ms\tjanks\tkeys\trepeats\tfirst_frame_ms\tproc_cpu%%\tsys_cpu%%\tgpu%%\tgpu_MHz\tsoc_C\trss_MB\n" > "$out"

systemctl stop gdm
trap 'echo dmc_ondemand > /sys/class/devfreq/dmc/governor; systemctl start gdm' EXIT
trap 'exit 1' INT TERM   # so that the desktop comes back on Ctrl-C too
export QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms QSG_INFO=1
cfg=/dev/shm/uispike-kms.json

nav() {   # about a minute of browsing: steps along a row, rests, holds a key, changes rows; Esc ends the run
    lap=1
    while [ $lap -le 3 ]; do
        for r in 1 2 3; do
            for i in 1 2 3 4 5 6; do echo right; echo "wait 160"; done
            echo "wait 900"
            echo "right 1500"   # held: Qt repeats it
            echo "wait 700"
            echo down
            echo "wait 600"
        done
        for i in 1 2 3 4 5 6 7 8; do echo left; echo "wait 120"; done
        echo "left 1200"
        echo "wait 600"
        echo up
        echo "wait 400"
        lap=$((lap + 1))
    done
    echo esc
}

run() {   # NAME ATOMIC MODE [FRAMEBUFFER]   a framebuffer smaller than the mode needs ATOMIC=1
    size=
    [ $# -ge 4 ] && size=", \"size\": \"$4\""
    printf '{ "device": "/dev/dri/card0", "hwcursor": false, "outputs": [ { "name": "HDMI1", "mode": "%s"%s } ] }\n' \
        "$3" "$size" > $cfg
    echo "$(date +%T) $1" >> progress.log
    QT_QPA_EGLFS_KMS_CONFIG=$cfg QT_QPA_EGLFS_KMS_ATOMIC=$2 timeout -s KILL 150 uispike/build/uispike "$1" "$3" \
        > /dev/shm/uispike.out 2>> errors.log &
    app=$!
    sleep 4   # the app is up and showing the home screen
    nav | ./keys 2>> errors.log
    wait $app
    grep -v arm_release /dev/shm/uispike.out >> "$out" || printf "%s\t-\t%s\tFAILED\n" "$1" "$3" >> "$out"
    sleep 15   # let the SoC cool a little
}

run ui-1080 0 1920x1080@60
run ui-1080-atomic 1 1920x1080@60
run ui-fb2160-on-1080 1 1920x1080@60 3840x2160
echo performance > /sys/class/devfreq/dmc/governor   # the memory clock at its highest: is memory the limit?
run ui-fb2160-on-1080-dmc-max 1 1920x1080@60 3840x2160
echo dmc_ondemand > /sys/class/devfreq/dmc/governor
export UISPIKE_NO_STILLS=1   # what costs frames: the background stills?
run ui-1080-no-stills 0 1920x1080@60
unset UISPIKE_NO_STILLS
export UISPIKE_NO_POSTERS=1  # or any picture at all?
run ui-1080-no-pictures 0 1920x1080@60
run ui-fb2160-on-1080-no-pictures 1 1920x1080@60 3840x2160
unset UISPIKE_NO_POSTERS
if [ -n "$mode4k" ]; then
    run ui-2160 0 "$mode4k"
    run ui-2160-atomic 1 "$mode4k"
    run ui-fb1080-on-2160 1 "$mode4k" 1920x1080
fi
echo "$(date +%T) done: $out" >> progress.log
