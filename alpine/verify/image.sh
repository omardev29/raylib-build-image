#!/bin/sh
# Proves the Alpine run image is what alpine/Dockerfile claims, run INSIDE it
# -- with no network, the way the framework's job runs it, and with an init,
# because xvfb-run must not be PID 1:
#
#   docker run --rm --init --network none -e EXPECT_ARCH=amd64 \
#       -v "$PWD/alpine/verify:/verify:ro" IMAGE sh /verify/image.sh
#
# alpine-image.yaml runs it on the image it built, before anything publishes
# it. Not COPYed into the image: changing a check here does not rebuild it.
#
# POSIX sh and busybox: the image has no bash, and is not getting one for this.
set -eu

: "${EXPECT_ARCH:?EXPECT_ARCH must be amd64}"

MANIFEST=/etc/raylib-run-alpine.json
cat "$MANIFEST"

# The architecture, twice: what the manifest says, and what apk says.
grep -q "\"arch\": \"${EXPECT_ARCH}\"" "$MANIFEST" \
    || { echo "FAIL: the manifest's arch is not ${EXPECT_ARCH}" >&2; exit 1; }
case "${EXPECT_ARCH}:$(apk --print-arch)" in
    amd64:x86_64) ;;
    *) echo "FAIL: EXPECT_ARCH=${EXPECT_ARCH} and apk says $(apk --print-arch); this image is amd64 only" >&2
       exit 1 ;;
esac

# The Alpine the manifest names is the Alpine this is.
grep -q "\"alpine\": \"$(cat /etc/alpine-release)\"" "$MANIFEST" \
    || { echo "FAIL: the manifest names another Alpine than /etc/alpine-release" >&2; exit 1; }

# Every package the Dockerfile asked for, with a version, in the manifest.
requested=$(sed -nE 's/^  "requested": "([^"]+)",$/\1/p' "$MANIFEST")
[ -n "$requested" ] || { echo "FAIL: the manifest lists no requested packages" >&2; exit 1; }
for p in $requested; do
    grep -q "^    \"$p\": \"[^\"]" "$MANIFEST" \
        || { echo "FAIL: $p was requested and the manifest has no version for it" >&2; exit 1; }
done

# musl's loader, which the shipped binary names as its interpreter.
test -e /lib/ld-musl-x86_64.so.1

# Every tool the job starts, started -- not just looked for.
command -v xvfb-run
command -v Xvfb
command -v xauth
command -v timeout

# The job in miniature: a GLX context on llvmpipe, a triangle, its pixels.
timeout 120 xvfb-run -a -s "-screen 0 64x64x24" rmp-glx-smoke > /tmp/smoke.log 2>&1 \
    || { cat /tmp/smoke.log; echo "FAIL: the GLX smoke check failed" >&2; exit 1; }
cat /tmp/smoke.log
grep -q '^RMP_GLX_SMOKE_OK .*llvmpipe' /tmp/smoke.log

echo "OK: linux/${EXPECT_ARCH} verified"
