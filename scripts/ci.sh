#!/bin/sh
# Everything CI checks (step 1.1), in one script that runs the same anywhere: on GitHub's arm64 runner
# (.github/workflows/ci.yml), in CI's environment in Docker on the PC (sh scripts/in-docker.sh sh scripts/ci.sh),
# or on any Ubuntu 22.04 with the packages from scripts/ci-deps.sh.
#
#   1. formatting (scripts/format.sh --check)
#   2. the app: configure, build with warnings as errors, run its tests (Qt Test, Qt Quick Test; offscreen)
#   3. the tests of the shell scripts and the board's tools
#
# usage: ci.sh            (exit status 0 when everything passes)
# Environment: RK3568_TV_CI_BUILD  the build folder (default build-ci; git ignores build-*)
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
build=${RK3568_TV_CI_BUILD:-$root/build-ci}
failed=

step() { printf '\n== %s\n' "$*"; }
fail() { failed="$failed
  $*"; }

step "formatting"
sh scripts/format.sh --check || fail "formatting (fix: sh scripts/format.sh)"

step "app: configure and build"
# The Mali libraries exist only on the board; a build elsewhere goes without them
if cmake -S app -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DRK3568_TV_LINK_MALI=OFF \
    -DCMAKE_CXX_FLAGS=-Werror > "$build.configure.log" 2>&1 \
    || { cat "$build.configure.log"; false; }; then
    if cmake --build "$build"; then
        step "app: tests"
        ctest --test-dir "$build" --output-on-failure || fail "the app's tests"
    else
        fail "the app's build"
    fi
else
    fail "configuring the app"
fi
rm -f "$build.configure.log"

for t in scripts/tests/test-*.sh system/tests/test-*.sh; do
    step "$t"
    out=$(sh "$t" 2>&1)
    status=$?
    printf '%s\n' "$out" | grep -v '^ok '   # the failures and the summary
    [ "$status" -eq 0 ] || fail "$t"
done

if [ -n "$failed" ]; then
    printf '\nFAILED:%s\n' "$failed"
    exit 1
fi
printf '\nAll checks passed.\n'
