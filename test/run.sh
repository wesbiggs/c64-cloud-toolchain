#!/bin/sh
# SPDX-License-Identifier: MIT
# Build test/hello.c, put it on a disk and boot it in x64sc from the disk:
# exits 0 if the toolchain works (see hello.c). Uses whatever cl65, c1541
# and x64sc are on the PATH.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

cl65 --version 2>&1 | head -1
x64sc --version 2>&1 | grep -m1 -i vice || true

cl65 -t c64 -O -o "$out/hello.prg" "$here/hello.c"
c1541 -format "hello,ct" d64 "$out/hello.d64" \
      -write "$out/hello.prg" hello >/dev/null

# A cycle limit in case it never gets there: x64sc then exits 1.
set +e
x64sc -default -silent +sound -warp -debugcart \
      -drive8type 1541 -drive8truedrive \
      -limitcycles 100000000 \
      -autostart "$out/hello.d64" >"$out/vice.log" 2>&1
code=$?
set -e

case $code in
    0) echo "smoke test: passed" ;;
    1) echo "smoke test: FAILED, it never finished (or VICE failed)"; tail -20 "$out/vice.log" ;;
    2) echo "smoke test: FAILED, the screen" ;;
    3) echo "smoke test: FAILED, the character ROM" ;;
    *) echo "smoke test: FAILED, exit $code"; tail -20 "$out/vice.log" ;;
esac
exit $code
