#!/bin/sh
# Tests for scripts/board.sh. A stub ssh records what would run on the board, so they run anywhere with a POSIX
# shell and tar (the PC's Git Bash, the board).
# usage: sh scripts/tests/test-board.sh   (exit status 0 when all tests pass)
set -u

here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
failures=0

check() {   # DESCRIPTION COMMAND...
    desc=$1
    shift
    if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; failures=$((failures + 1)); fi
}
has() { grep -qF -- "$2" "$1"; }      # FILE TEXT
hasnt() { ! grep -qF -- "$2" "$1" 2> /dev/null; }
absent() { [ ! -e "$1" ]; }

# A repository of our own: board.sh finds the sources next to itself
repo=$T/repo
mkdir -p "$repo/scripts" "$repo/app/qml" "$repo/app/build" "$repo/app/build-x"
cp "$here/../board.sh" "$repo/scripts/"
echo 'cmake_minimum_required(VERSION 3.16)' > "$repo/app/CMakeLists.txt"
echo 'import QtQuick' > "$repo/app/qml/Main.qml"
echo stale > "$repo/app/build/stale.o"
echo stale > "$repo/app/build-x/stale.o"
echo '#!/bin/sh' > "$repo/scripts/board-run.sh"
echo 'int main(void) { return 0; }' > "$repo/scripts/board-keys.c"
printf 'BOARD=root@board.test\r\n' > "$repo/.env"   # a Windows editor's line ending

# the stub: arguments to ssh.args, stdin to ssh.stdin; a screenshot unless SSH_EMPTY; exit status SSH_STATUS
mkdir "$T/bin"
cat > "$T/bin/ssh" << EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/ssh.args"
cat > "$T/ssh.stdin"
case "\$*" in *kmsgrab*) [ -n "\${SSH_EMPTY:-}" ] || printf PNGDATA ;; esac
exit \${SSH_STATUS:-0}
EOF
chmod +x "$T/bin/ssh"
PATH=$T/bin:$PATH
export PATH
unset BOARD SSH_STATUS SSH_EMPTY RK3568_TV_ENV

run() {   # ARGS...: board.sh's exit status to $T/status, its output to $T/out
    rm -f "$T/ssh.args" "$T/ssh.stdin"
    sh "$repo/scripts/board.sh" "$@" < /dev/null > "$T/out" 2>&1
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }

run
check "no command: usage, exit 2" status 2
check "no command: usage text" has "$T/out" "usage: board.sh deploy"
run reboot
check "unknown command: exit 2" status 2
check "unknown command: ssh not run" hasnt "$T/ssh.args" ssh

RK3568_TV_ENV=$T/none run logs
check "no address: exit 1" status 1
check "no address: says where to put it" has "$T/out" "BOARD=root@<address> into $T/none"
check "no address: ssh not run" hasnt "$T/ssh.args" board

run logs
check "address from .env, without the carriage return" has "$T/ssh.args" "root@board.test journalctl -u rk3568-tv-dev -n 100 --no-pager"
check "logs: exit 0" status 0
BOARD=root@other.test run logs -f
check "BOARD wins over .env; logs -f follows" has "$T/ssh.args" "root@other.test journalctl -u rk3568-tv-dev -n 50 -f"
run logs --all
check "logs with a bad option: exit 2" status 2

run deploy
tar -tf "$T/ssh.stdin" > "$T/listing"
check "deploy: sends the app" has "$T/listing" app/qml/Main.qml
check "deploy: sends the board's scripts" has "$T/listing" scripts/board-run.sh
check "deploy: sends the keys tool" has "$T/listing" scripts/board-keys.c
check "deploy: no build trees" hasnt "$T/listing" stale.o
check "deploy: not board.sh itself" hasnt "$T/listing" scripts/board.sh
check "deploy: replaces the sources" has "$T/ssh.args" "rm -rf /userdata/dev/rk3568-tv/app /userdata/dev/rk3568-tv/scripts"
check "deploy: keeps file times, not owners" has "$T/ssh.args" "tar -xf - --no-same-owner -C /userdata/dev/rk3568-tv"
check "deploy: builds and starts on the board" has "$T/ssh.args" "sh /userdata/dev/rk3568-tv/scripts/board-run.sh"
check "deploy: exit 0" status 0
check "deploy: tells the time it took" has "$T/out" "board: deploy took"
SSH_STATUS=1 run deploy
check "deploy: a failure on the board fails it" status 1

run test
check "test: sends the app" sh -c "tar -tf '$T/ssh.stdin' | grep -q app/qml/Main.qml"
check "test: board-run.sh runs the tests" has "$T/ssh.args" "sh /userdata/dev/rk3568-tv/scripts/board-run.sh test"
check "test: tells the time it took" has "$T/out" "board: test took"
SSH_STATUS=8 run test
check "test: failing tests fail it" status 8

run shot "$T/shots/a.png"
check "shot: the picture in FILE" has "$T/shots/a.png" PNGDATA
check "shot: names the file" has "$T/out" "$T/shots/a.png"
check "shot: grabs with kmsgrab" has "$T/ssh.args" "-f kmsgrab"
run shot
check "shot: screenshots/latest.png by default" has "$repo/screenshots/latest.png" PNGDATA
SSH_EMPTY=1 run shot "$T/shots/b.png"
check "shot: an empty picture fails" status 1
check "shot: and leaves no file" absent "$T/shots/b.png"
check "shot: nor a part file" absent "$T/shots/b.png.part"
SSH_STATUS=255 run shot "$T/shots/c.png"
check "shot: ssh failing fails it" status 1

run keys right right:1500 wait:300 enter
check "keys: pressed on the board" has "$T/ssh.args" "/userdata/dev/rk3568-tv/build/board-keys right right:1500 wait:300 enter"
check "keys: exit 0" status 0
run keys 'right;reboot'
check "keys: refuses anything but a key" status 1
check "keys: and runs nothing" hasnt "$T/ssh.args" reboot
run keys
check "keys without a key: usage" status 2

run stop
check "stop: board-run.sh stops the app on the board" has "$T/ssh.args" "sh /userdata/dev/rk3568-tv/scripts/board-run.sh stop"

echo "$failures failed"
[ "$failures" -eq 0 ]
