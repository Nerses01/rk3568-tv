#!/bin/sh
# The development loop, run on the developer's PC (Git Bash on Windows, or any POSIX shell; steps 0.7 and 1.2). The
# app goes to the board, is built and installed there and runs on the screen as at boot (rk3568-tv.service); its log,
# a screenshot and key presses come back over SSH, so a change can be checked without sitting at the TV.
#
# usage: board.sh deploy        copy app/ to the board, build and install it there, restart it on the screen
#        board.sh test          copy app/ to the board, build everything there and run the tests
#        board.sh logs [-f]     the app's log: the last 100 lines, or follow it
#        board.sh shot [FILE]   a screenshot of the board's screen, to FILE (default screenshots/latest.png)
#        board.sh keys KEY...   press keys on the board, e.g. `board.sh keys right right enter`
#                               (keys and hold times: scripts/board-keys.c)
#        board.sh stop          stop the app and start the desktop (GNOME), until the next boot or deploy
#        board.sh mode [MODE]   what the board boots into: tv, desktop, or (no MODE) show it (rk3568-tv-mode)
#
# The board's address comes from BOARD, or from a line BOARD=root@<address> in the repository's .env, which git
# ignores (RK3568_TV_ENV names another file). Needs ssh with key login, and tar.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
dir=/userdata/dev/rk3568-tv   # on the board
unit=rk3568-tv

die() {
    echo "board: $*" >&2
    exit 1
}

usage() {
    cat >&2 << 'EOF'
usage: board.sh deploy        copy app/ to the board, build and install it there, restart it on the screen
       board.sh test          copy app/ to the board, build everything there and run the tests
       board.sh logs [-f]     the app's log: the last 100 lines, or follow it
       board.sh shot [FILE]   a screenshot of the board's screen (default screenshots/latest.png)
       board.sh keys KEY...   press keys on the board, e.g. board.sh keys right right enter
       board.sh stop          stop the app and start the desktop, until the next boot or deploy
       board.sh mode [MODE]   what the board boots into: tv, desktop, or (no MODE) show it
EOF
    exit 2
}

need_board() {
    env_file=${RK3568_TV_ENV:-$root/.env}
    if [ -z "${BOARD:-}" ] && [ -f "$env_file" ]; then
        BOARD=$(sed -n 's/^BOARD=//p' "$env_file" | tail -n 1 | tr -d "\r\"'")
    fi
    [ -n "${BOARD:-}" ] || die "no board address: put BOARD=root@<address> into $env_file"
}

on_board() {
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$BOARD" "$@"
}

send_and_run() {   # [ARG]: copy the sources to the board, then run board-run.sh [ARG] there
    start=$(date +%s)
    cd "$root" || exit 1
    # File times travel with the files, so the board rebuilds only what changed.
    tar -cf - --exclude=build --exclude='build-*' --exclude=system/tests app system scripts/board-run.sh scripts/board-keys.c |
        on_board "rm -rf $dir/app $dir/system $dir/scripts && mkdir -p $dir && tar -xf - --no-same-owner -C $dir &&
                  sh $dir/scripts/board-run.sh $*"
    status=$?
    echo "board: ${*:-deploy} took $(($(date +%s) - start)) s"
    return $status
}

logs() {
    case ${1:-} in
    -f) on_board "journalctl -u $unit -n 50 -f --no-pager" ;;
    '') on_board "journalctl -u $unit -n 100 --no-pager" ;;
    *) usage ;;
    esac
}

shot() {
    file=${1:-$root/screenshots/latest.png}
    mkdir -p "$(dirname "$file")" || exit 1
    # kmsgrab reads the framebuffer that the display shows, whoever drew it
    on_board "ffmpeg -hide_banner -loglevel error -f kmsgrab -i - -vf hwdownload,format=bgr0 -frames:v 1 \
              -f image2pipe -vcodec png -" > "$file.part" || {
        rm -f "$file.part"
        die "the screenshot failed"
    }
    [ -s "$file.part" ] || {
        rm -f "$file.part"
        die "the screenshot is empty"
    }
    mv "$file.part" "$file" && echo "$file"
}

keys() {
    [ $# -gt 0 ] || usage
    for k; do
        case $k in
        '' | *[!a-z0-9:]*) die "not a key: '$k'" ;;
        esac
    done
    on_board "$dir/build/board-keys $*"
}

stop() {
    on_board "sh $dir/scripts/board-run.sh stop"
}

mode() {
    case ${1:-status} in
    tv | desktop | status) on_board "rk3568-tv-mode ${1:-status}" ;;
    *) usage ;;
    esac
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
deploy | test | logs | shot | keys | stop | mode) need_board ;;
*) usage ;;
esac
case $cmd in
deploy) send_and_run ;;
test) send_and_run test ;;
logs) logs "$@" ;;
shot) shot "$@" ;;
keys) keys "$@" ;;
stop) stop ;;
mode) mode "$@" ;;
esac
