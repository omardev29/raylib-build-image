#!/usr/bin/env bash
# Proves the image contains what the Dockerfile claims, run INSIDE it, on the
# architecture it was built for:
#
#   docker run --rm -e EXPECT_ARCH=amd64 -v "$PWD/verify:/verify:ro" IMAGE bash -l /verify/image.sh
#
# The workflow runs it in each build job, on a runner of that architecture, on
# the image that job built -- before anything is published. It is not COPYed
# into the image (smoke/ is): changing a check here does not rebuild a layer.
#
# The manifest's own `arch` field is compared with the architecture asked for:
# that is what catches an image built for the wrong platform, which no amount
# of `cmake --version` would notice.
set -euo pipefail

: "${EXPECT_ARCH:?EXPECT_ARCH must be amd64 or arm64}"

cat /etc/raylib-build-image.json
grep -q "\"arch\": \"${EXPECT_ARCH}\"" /etc/raylib-build-image.json
test "$(dpkg --print-architecture)" = "${EXPECT_ARCH}"

cmake --version | head -1
ninja --version
zig version
emcc --version | head -1
gcc --version | head -1
aarch64-linux-gnu-gcc --version | head -1
objdump --version | head -1
upx --version | head -1
clang-format --version
python3 -c "import yaml, PIL, tomllib; print('python deps ok')"
# The test toolchain (phase 15/16): LLVM 18 tools, cppcheck, Mull, the Python
# test tools, and the manifest keys that versions_check.sh compares against the
# framework pins.
llvm-cov --version | head -2
llvm-profdata --version | head -2
cppcheck --version
mull-runner-18 --version | head -1
test -f /usr/lib/mull-ir-frontend-18
python3 -c "import hypothesis, mutmut, pytest; print('hypothesis', hypothesis.__version__, 'pytest', pytest.__version__)"
for key in llvm cppcheck mull hypothesis mutmut pytest; do
    grep -q "\"${key}\": \"[^\"]" /etc/raylib-build-image.json
done

# Android, butler and actionlint are amd64-only by construction (see their
# install steps in the Dockerfile). Their presence is asserted there, and
# their documented absence on arm64, so the difference stays a decision rather
# than turning into a 2 a.m. surprise.
case "${EXPECT_ARCH}" in
    amd64)
        test -d "$ANDROID_NDK_HOME"
        butler -V
        actionlint --version
        # The Gradle home that lets the Android job build --offline.
        cat "$GRADLE_USER_HOME/rmp-warm.properties"
        for key in gradle agp play_services_ads gradle_warm_commit; do
            grep -q "\"${key}\": \"[^\"]" /etc/raylib-build-image.json
        done
        echo "OK: amd64-only tools present"
        ;;
    arm64)
        if [ -d "${ANDROID_NDK_HOME:-/nonexistent}" ]; then
            echo "FAIL: arm64 image unexpectedly carries the Android NDK" >&2
            exit 1
        fi
        if [ -e "${GRADLE_USER_HOME:-/nonexistent}/rmp-warm.properties" ] ||
            grep -q "\"gradle\":" /etc/raylib-build-image.json; then
            echo "FAIL: arm64 image unexpectedly carries a warmed Gradle home" >&2
            exit 1
        fi
        echo "OK: arm64 documented differences hold"
        ;;
    *)
        echo "FAIL: EXPECT_ARCH=${EXPECT_ARCH}, and this image is built for amd64 and arm64" >&2
        exit 1
        ;;
esac

echo "OK: linux/${EXPECT_ARCH} verified"
