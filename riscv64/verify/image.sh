#!/bin/sh
# Proves the riscv64 build image is what riscv64/Dockerfile claims, run INSIDE
# it, on RISC-V hardware, with no network and with an init (xvfb-run must not
# be PID 1):
#
#   docker run --rm --init --network none \
#       -v "$PWD/riscv64/verify:/verify:ro" IMAGE sh /verify/image.sh
#
# riscv64-image.yaml runs it on the image it built, before anything publishes
# it. Not COPYed into the image: changing a check here does not rebuild it.
set -eu

MANIFEST=/etc/raylib-build-riscv64.json
cat "$MANIFEST"
python3 -m json.tool "$MANIFEST" > /dev/null

# The architecture, three ways: the manifest, dpkg, and the kernel.
grep -q '"arch": "riscv64"' "$MANIFEST" || { echo "FAIL: the manifest's arch is not riscv64" >&2; exit 1; }
[ "$(dpkg --print-architecture)" = riscv64 ] || { echo "FAIL: dpkg says $(dpkg --print-architecture)" >&2; exit 1; }
[ "$(uname -m)" = riscv64 ] || { echo "FAIL: the kernel says $(uname -m): not RISC-V hardware" >&2; exit 1; }

# The pins the framework compares (thirdparty/FROZEN_VERSIONS.md).
grep -q '"cmake": "3.30.3"' "$MANIFEST" || { echo "FAIL: cmake is not 3.30.3" >&2; exit 1; }
grep -q '"upx": "5.2.0"' "$MANIFEST"    || { echo "FAIL: upx is not 5.2.0" >&2; exit 1; }
grep -q '"ubuntu": "24.04"' "$MANIFEST" || { echo "FAIL: not Ubuntu 24.04" >&2; exit 1; }

# Every tool the framework's job starts, started -- not just looked for.
for t in gcc g++ cmake ninja upx python3 objdump zip unzip pkg-config xvfb-run Xvfb xauth timeout git; do
    command -v "$t" > /dev/null || { echo "FAIL: no $t" >&2; exit 1; }
done
gcc --version | head -1
cmake --version | head -1
upx --version | head -1

# The job in miniature, part one: CMake + Ninja + g++ build a C++20 program
# against X11 and GL, and UPX packs it and the packed copy still runs.
WORK=$(mktemp -d)
cat > "$WORK/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.30)
project(probe CXX)
set(CMAKE_CXX_STANDARD 20)
find_package(X11 REQUIRED)
find_package(OpenGL REQUIRED)
add_executable(probe main.cpp)
target_link_libraries(probe PRIVATE X11::X11 OpenGL::GL)
EOF
cat > "$WORK/main.cpp" <<'EOF'
#include <X11/Xlib.h>
#include <GL/gl.h>
#include <cstdio>
#include <span>
int main() { int a[3] = {1, 2, 3}; std::span<int> s(a); std::printf("PROBE_OK %zu\n", s.size()); return 0; }
EOF
cmake -S "$WORK" -B "$WORK/build" -G Ninja -DCMAKE_BUILD_TYPE=Release > /dev/null
cmake --build "$WORK/build" > /dev/null
"$WORK/build/probe" | grep -q '^PROBE_OK 3$' || { echo "FAIL: the probe did not run" >&2; exit 1; }
cp "$WORK/build/probe" "$WORK/packed"
upx -q "$WORK/packed" > /dev/null
"$WORK/packed" | grep -q '^PROBE_OK 3$' || { echo "FAIL: the UPX-packed probe did not run" >&2; exit 1; }
rm -rf "$WORK"

# Part two: a GLX context on llvmpipe, a triangle, its pixels.
timeout 300 xvfb-run -a -s "-screen 0 64x64x24" rmp-glx-smoke > /tmp/smoke.log 2>&1 \
    || { cat /tmp/smoke.log; echo "FAIL: the GLX smoke check failed" >&2; exit 1; }
cat /tmp/smoke.log
grep -q '^RMP_GLX_SMOKE_OK .*llvmpipe' /tmp/smoke.log

echo "OK: linux/riscv64 verified"
