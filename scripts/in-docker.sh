#!/bin/sh
# Runs a command in CI's environment on the PC: Ubuntu 22.04 with the packages from scripts/ci-deps.sh, the
# repository mounted at /src (step 1.1). For a PC without Qt or clang-format, e.g.
#   sh scripts/in-docker.sh sh scripts/ci.sh          everything CI checks
#   sh scripts/in-docker.sh sh scripts/format.sh      format the app's C++ and QML
# The image is built on first use, and again whenever ci-deps.sh changes. Needs Docker.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
image=rk3568-tv-ci:$(cksum < "$root/scripts/ci-deps.sh" | cut -d ' ' -f 1)

[ $# -gt 0 ] || {
    echo "usage: in-docker.sh COMMAND..." >&2
    exit 2
}
docker image inspect "$image" > /dev/null 2>&1 ||
    docker build -t "$image" -f "$root/scripts/ci.Dockerfile" "$root/scripts" || exit 1

if command -v cygpath > /dev/null; then
    # Git Bash: Docker wants a Windows path, and MSYS must not rewrite /src
    MSYS_NO_PATHCONV=1 exec docker run --rm -v "$(cygpath -w "$root"):/src" -w /src "$image" "$@"
fi
exec docker run --rm --user "$(id -u):$(id -g)" -v "$root:/src" -w /src "$image" "$@"
