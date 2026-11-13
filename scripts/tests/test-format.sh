#!/bin/sh
# Tests for scripts/format.sh, with stub formatters, so they run anywhere with a POSIX shell.
# usage: sh scripts/tests/test-format.sh   (exit status 0 when all tests pass)
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

# A repository of our own: format.sh works on the files next to it
repo=$T/repo
mkdir -p "$repo/scripts" "$repo/app/src" "$repo/app/qml" "$repo/app/build/x" "$repo/spikes"
cp "$here/../format.sh" "$repo/scripts/"
reset() {
    echo 'int a;' > "$repo/app/src/a.cpp"
    echo 'int b;' > "$repo/app/src/b.h"
    echo 'int k;' > "$repo/scripts/keys.c"
    echo 'Item {}' > "$repo/app/qml/Main.qml"
    echo 'int z;' > "$repo/app/build/x/gen.cpp"
    echo 'int s;' > "$repo/spikes/s.cpp"
}
reset

# The stubs format by putting a FORMATTED line first; qmlformat fails on an arrow function, as qmlformat 6.2 does
mkdir "$T/bin"
cat > "$T/bin/fake-format" << 'EOF'
#!/bin/sh
for f; do :; done
head -n 1 "$f" | grep -q FORMATTED || echo FORMATTED
cat "$f"
EOF
cat > "$T/bin/fake-qmlformat" << 'EOF'
#!/bin/sh
grep -q '=>' "$1" && { echo "writeOut created invalid code" >&2; exit 1; }
head -n 1 "$1" | grep -q FORMATTED || echo FORMATTED
cat "$1"
EOF
chmod +x "$T/bin/fake-format" "$T/bin/fake-qmlformat"
export CLANG_FORMAT=$T/bin/fake-format QMLFORMAT=$T/bin/fake-qmlformat

run() {   # ARGS...: output to $T/out, exit status to $T/status
    sh "$repo/scripts/format.sh" "$@" > "$T/out" 2>&1
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }
formatted() { head -n 1 "$1" | grep -q FORMATTED; }
unformatted() { ! formatted "$1"; }

run --check
check "check: unformatted files fail it" status 1
check "check: names the C++" has "$T/out" "not formatted: app/src/a.cpp"
check "check: names the headers" has "$T/out" "not formatted: app/src/b.h"
check "check: names the board's C" has "$T/out" "not formatted: scripts/keys.c"
check "check: names the QML" has "$T/out" "not formatted: app/qml/Main.qml"
check "check: changes nothing" unformatted "$repo/app/src/a.cpp"
check "check: skips build trees" hasnt "$T/out" gen.cpp
check "check: skips the spikes" hasnt "$T/out" s.cpp

run
check "format: exit 0" status 0
check "format: the C++ is formatted" formatted "$repo/app/src/a.cpp"
check "format: the QML is formatted" formatted "$repo/app/qml/Main.qml"
check "format: says what it formatted" has "$T/out" "formatted: app/src/b.h"
check "format: build trees untouched" unformatted "$repo/app/build/x/gen.cpp"
check "format: spikes untouched" unformatted "$repo/spikes/s.cpp"

run --check
check "check after format: exit 0" status 0
check "check after format: says nothing" sh -c "[ ! -s '$T/out' ]"

echo 'Item { onX: x => { } }' > "$repo/app/qml/Main.qml"
run
check "a formatter that fails: exit 1" status 1
check "a formatter that fails: its file is named" has "$T/out" "failed on app/qml/Main.qml"
check "a formatter that fails: its message is shown" has "$T/out" "created invalid code"
check "a formatter that fails: the file is left alone" has "$repo/app/qml/Main.qml" "x => { }"
check "a formatter that fails: the others are still formatted" formatted "$repo/app/src/a.cpp"

run --fix
check "an unknown option: exit 2" status 2

CLANG_FORMAT=$T/none run --check
check "no clang-format: exit 1" status 1
check "no clang-format: says how to run it in Docker" has "$T/out" "sh scripts/in-docker.sh sh scripts/format.sh"

echo "$failures failed"
[ "$failures" -eq 0 ]
