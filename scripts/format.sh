#!/bin/sh
# Formats the C++ and QML of app/ and the C of scripts/ (step 1.1): clang-format with the style in .clang-format,
# qmlformat with its defaults. With --check it changes nothing, names each file that is not formatted, and exits 1.
#
# usage: format.sh [--check]
#
# The reference versions are Ubuntu 22.04's, as in CI: clang-format 14 and qmlformat 6.2.4. Without them (on
# Windows, say), run it in CI's environment: sh scripts/in-docker.sh sh scripts/format.sh
# CLANG_FORMAT and QMLFORMAT name other binaries.
#
# qmlformat 6.2 turns some JavaScript into invalid code, and then fails. In QML, write `function (x) { ... }`, not
# an arrow function (`x => { ... }` in a handler, `() => a` as an argument), and `for (const x of list)`, not
# `for (let i = 0; ...)`.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
check=false
case ${1:-} in
--check) check=true ;;
'') ;;
*)
    echo "usage: format.sh [--check]" >&2
    exit 2
    ;;
esac

clang_format=${CLANG_FORMAT:-clang-format}
qmlformat=${QMLFORMAT:-$(command -v qmlformat || echo /usr/lib/qt6/bin/qmlformat)}
command -v "$clang_format" > /dev/null || {
    echo "format: no $clang_format; try: sh scripts/in-docker.sh sh scripts/format.sh" >&2
    exit 1
}
[ -x "$qmlformat" ] || {
    echo "format: no qmlformat; try: sh scripts/in-docker.sh sh scripts/format.sh" >&2
    exit 1
}

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp" "$tmp.err"' EXIT
status=0

# FILE FORMATTER...: the formatter writes the formatted FILE to stdout
one() {
    file=$1
    shift
    if ! "$@" "$file" > "$tmp" 2> "$tmp.err"; then
        echo "format: $* failed on $file:" >&2
        cat "$tmp.err" >&2
        status=1
    elif ! cmp -s "$tmp" "$file"; then
        if $check; then
            echo "not formatted: $file"
            status=1
        else
            cat "$tmp" > "$file" && echo "formatted: $file"
        fi
    fi
}

for f in $(find app scripts -path '*/build*' -prune -o \( -name '*.cpp' -o -name '*.h' -o -name '*.c' \) -print | sort); do
    one "$f" "$clang_format" --style=file
done
for f in $(find app -path '*/build*' -prune -o -name '*.qml' -print | sort); do
    one "$f" "$qmlformat"
done
exit $status
