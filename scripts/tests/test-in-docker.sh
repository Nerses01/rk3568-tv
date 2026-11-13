#!/bin/sh
# Tests for scripts/in-docker.sh, with a stub docker, so they run anywhere with a POSIX shell.
# usage: sh scripts/tests/test-in-docker.sh   (exit status 0 when all tests pass)
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

repo=$T/repo
mkdir -p "$repo/scripts"
cp "$here/../in-docker.sh" "$repo/scripts/"
echo 'apt-get install -y cmake' > "$repo/scripts/ci-deps.sh"
tag=$(cksum < "$repo/scripts/ci-deps.sh" | cut -d ' ' -f 1)

# docker: records its calls; `image inspect` fails unless HAVE_IMAGE. cygpath: as Git Bash's, C:\ for /
mkdir "$T/bin" "$T/win"
cat > "$T/bin/docker" << EOF
#!/bin/sh
printf '%s\n' "docker \$* MSYS_NO_PATHCONV=\${MSYS_NO_PATHCONV:-}" >> "$T/calls"   # not echo: dash's reads \f
[ "\$1 \$2" = "image inspect" ] && [ -z "\${HAVE_IMAGE:-}" ] && exit 1
exit 0
EOF
cat > "$T/win/cygpath" << 'EOF'
#!/bin/sh
printf '%s\n' "C:\fake$2"
EOF
chmod +x "$T/bin/docker" "$T/win/cygpath"
unset HAVE_IMAGE

run() {   # PATH_PREFIX ARGS...: output to $T/out, exit status to $T/status
    p=$1
    shift
    rm -f "$T/calls"
    PATH=$p:$PATH sh "$repo/scripts/in-docker.sh" "$@" > "$T/out" 2>&1
    echo $? > "$T/status"
}
status() { [ "$(cat "$T/status")" = "$1" ]; }

run "$T/bin"
check "no command: usage, exit 2" status 2
check "no command: docker not run" hasnt "$T/calls" docker

run "$T/win:$T/bin" sh scripts/ci.sh
check "no image yet: it is built from ci.Dockerfile" has "$T/calls" "docker build -t rk3568-tv-ci:$tag -f $repo/scripts/ci.Dockerfile $repo/scripts"
check "Git Bash: a Windows path for the mount" has "$T/calls" "-v C:\\fake$repo:/src -w /src rk3568-tv-ci:$tag sh scripts/ci.sh"
check "Git Bash: MSYS leaves /src alone" has "$T/calls" "sh scripts/ci.sh MSYS_NO_PATHCONV=1"
check "exit 0" status 0

HAVE_IMAGE=1 run "$T/win:$T/bin" true
check "an image for these packages: no build" hasnt "$T/calls" "docker build"

echo 'apt-get install -y cmake ninja-build' > "$repo/scripts/ci-deps.sh"
run "$T/win:$T/bin" true
check "new packages: a new image" has "$T/calls" "docker build -t rk3568-tv-ci:$(cksum < "$repo/scripts/ci-deps.sh" | cut -d ' ' -f 1)"

if command -v cygpath > /dev/null; then
    echo "skip Linux: the mount as the user (cygpath is installed here)"
else
    HAVE_IMAGE=1 run "$T/bin" true
    check "Linux: the mount as it is, as the user" has "$T/calls" "--user $(id -u):$(id -g) -v $repo:/src -w /src"
fi

echo "$failures failed"
[ "$failures" -eq 0 ]
