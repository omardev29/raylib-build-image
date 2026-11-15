# raylib_multiplatform -- the image its riscv64 build runs in, on RISC-V
#
#   ghcr.io/omardev29/raylib-build-riscv64
#
# The framework's linux-riscv64-glibc target is built twice over, by choice:
# natively, on a RISE RISC-V runner (`runs-on: ubuntu-24.04-riscv`, real
# hardware, free for open source and given at the RISE project's discretion),
# and, when RISE fails or has no board for the job, cross-compiled in the amd64
# build image and started under QEMU. This is the image of the first: the job
# runs on the RISE runner and enters this image with `docker run` for the
# commands that build, pack and start the game.
#
# WHY NOT THE BUILD IMAGE. ghcr.io/omardev29/raylib-build is amd64 and arm64,
# and most of what it carries has no riscv64 build at all -- zig's warmed libc++
# cache, Mull, emsdk, the Android SDK and NDK, the Gradle home, mingw, wine,
# xwin, Kitware's CMake binaries, UPX's release binaries. The riscv64 job needs
# none of those; it needs a C and C++ compiler, CMake, Ninja, Python, the
# X11/GL headers and an X server with Mesa to start the game on. So this image
# is that, and only that, built and verified ON a RISC-V machine.
#
# SAME TOOLCHAIN AS THE CROSS BUILD, ON PURPOSE. The fallback cross-compiles
# with Ubuntu 24.04's riscv64-linux-gnu-gcc 13 against Ubuntu 24.04's riscv64
# glibc; this image is Ubuntu 24.04 riscv64 with its native gcc 13 and that
# same glibc, from the SAME apt snapshot the build image is frozen to. So the
# two paths make the same binary for the same commit: one size line in
# tools/size_budget.txt, one glibc floor (2.38), whichever path ran.
#
# EVERYTHING IS PINNED: the base by digest (the same ubuntu:24.04 index the
# build image pins, whose riscv64 entry this is), apt by snapshot timestamp,
# and every source tarball by sha256. CMake has no riscv64 release binary, so
# it is built here from its release source, at the version the build image
# carries (3.30.3). Ninja is noble's ninja-build, 1.11.1, from the snapshot:
# its source tarball is not served to every network this file is edited on,
# and nothing the framework does asks for 1.12.
#
# NO UPX. The framework never packs linux-riscv64-glibc: UPX 5.2.0's riscv64
# stub dies with SIGTRAP on every kernel before 6.3, RISE's 5.10 among them --
# memfd_create(MFD_EXEC) is EINVAL there, and that stub, unlike amd64's and
# arm64's, never tries again without the flag (raylib_multiplatform's
# CLAUDE.md). tools/upx_pack.sh leaves a target [upx] does not pack without
# calling upx at all.
#
#   docker build -t raylib-build-riscv64 riscv64/        # on a riscv64 machine

ARG UBUNTU_DIGEST=sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea
FROM ubuntu:24.04@${UBUNTU_DIGEST}
ARG UBUNTU_DIGEST

ARG APT_SNAPSHOT=20260801T000000Z
ARG CMAKE_VERSION=3.30.3
# Kitware's own cmake-3.30.3-SHA-256.txt lists this for cmake-3.30.3.tar.gz.
ARG CMAKE_SRC_SHA256=6d5de15b6715091df7f5441007425264bdd477809f80333fdf95f846aaff88e4

ENV DEBIAN_FRONTEND=noninteractive

# RISC-V only. Built anywhere else -- under QEMU on an amd64 runner, say -- it
# would be verified by an emulator, and what this image proves is that the
# real hardware builds and draws.
RUN set -eu; \
    arch="$(dpkg --print-architecture)"; \
    if [ "$arch" != riscv64 ]; then \
        echo "FAIL: this image is riscv64 only, and this build is ${arch}" >&2; \
        exit 1; \
    fi

# Apt frozen to the build image's snapshot (see the build image's Dockerfile:
# snapshot.ubuntu.com is HTTPS-only, so ca-certificates comes first, and the
# frozen Release file needs Check-Valid-Until off).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /etc/apt/sources.list.d/ubuntu.sources; \
    printf '%s\n' \
        "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT} noble main universe restricted multiverse" \
        "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT} noble-updates main universe restricted multiverse" \
        "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT} noble-security main universe restricted multiverse" \
        > /etc/apt/sources.list; \
    printf '%s\n' 'Acquire::Check-Valid-Until "false";' \
        > /etc/apt/apt.conf.d/99no-check-valid-until; \
    apt-get update

# What the framework's riscv64 job runs, and nothing else:
#   build-essential gcc g++  the compilers, gcc 13 like the cross toolchain
#   ninja-build              CMake's generator
#   binutils file            objdump for tools/glibc_check.sh, file for humans
#   python3 python3-yaml     tools/configure.py, size_check.py, binary_check.py
#   git curl xz-utils        fetching and unpacking the sources below
#   zip unzip                the archive the job ships, and opening it again
#   pkg-config               raylib's CMake asks it for X11
#   libx11-dev ... libgl1-mesa-dev, libwayland-dev libxkbcommon-dev
#   wayland-protocols        raylib's desktop build (GLFW with X11 and Wayland)
#   xvfb xauth libgl1-mesa-dri
#                            an X server and Mesa's llvmpipe, to start the game
#                            on; xauth is only a Recommends of xvfb
RUN apt-get install -y --no-install-recommends \
        build-essential gcc g++ \
        ninja-build \
        binutils file \
        python3 python3-yaml \
        git curl xz-utils \
        zip unzip \
        pkg-config \
        libx11-dev libxrandr-dev libxi-dev libxcursor-dev libxinerama-dev \
        libgl1-mesa-dev libwayland-dev libxkbcommon-dev wayland-protocols \
        xvfb xauth libgl1-mesa-dri \
    && rm -rf /var/lib/apt/lists/*

# CMake, from Kitware's release source (no riscv64 binary is released). No
# OpenSSL: nothing the framework's build downloads through CMake.
RUN set -eux; \
    cd /tmp; \
    curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}.tar.gz" \
        -o cmake.tar.gz; \
    echo "${CMAKE_SRC_SHA256}  cmake.tar.gz" | sha256sum -c -; \
    tar -xzf cmake.tar.gz; \
    cd "cmake-${CMAKE_VERSION}"; \
    ./bootstrap --prefix=/usr/local --parallel="$(nproc)" -- \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_USE_OPENSSL=OFF -DBUILD_TESTING=OFF; \
    make -j"$(nproc)"; \
    make install; \
    cd /; rm -rf /tmp/cmake*; \
    cmake --version | grep -q "cmake version ${CMAKE_VERSION}"

# The smoke program: a GLX context on llvmpipe, a triangle, its pixels read
# back (the same smoke/glx.c the Alpine run image proves itself with).
COPY smoke/glx.c /tmp/glx.c
RUN gcc -std=c99 -O2 -Wall -Wextra -Werror /tmp/glx.c -o /usr/local/bin/rmp-glx-smoke -lGL -lX11 -ldl \
    && strip /usr/local/bin/rmp-glx-smoke && rm /tmp/glx.c

# Manifest: what IS in the image, read from the tools themselves. The
# framework's job prints it first, and tools/versions_check.sh compares it with
# thirdparty/FROZEN_VERSIONS.md's riscv64 rows.
RUN set -eu; \
    kv() { printf '  "%s": "%s",\n' "$1" "$2"; }; \
    deb() { dpkg-query -W -f='${Version}' "$1"; }; \
    { \
      echo '{'; \
      kv image        raylib-build-riscv64; \
      kv arch         "$(dpkg --print-architecture)"; \
      kv ubuntu       "$(. /etc/os-release && echo "$VERSION_ID")"; \
      kv ubuntu_digest "${UBUNTU_DIGEST}"; \
      kv apt_snapshot "${APT_SNAPSHOT}"; \
      kv gcc          "$(gcc -dumpfullversion)"; \
      kv glibc        "$(ldd --version | sed -nE '1s/.* ([0-9]+\.[0-9]+)$/\1/p')"; \
      kv cmake        "$(cmake --version | sed -nE '1s/^cmake version ([0-9.]+)$/\1/p')"; \
      kv ninja        "$(ninja --version)"; \
      kv python       "$(python3 -c 'import platform; print(platform.python_version())')"; \
      printf '  "%s": "%s"\n' mesa "$(deb libgl1-mesa-dri)"; \
      echo '}'; \
    } > /etc/raylib-build-riscv64.json; \
    cat /etc/raylib-build-riscv64.json; \
    python3 -m json.tool /etc/raylib-build-riscv64.json > /dev/null; \
    if grep -n '": ""' /etc/raylib-build-riscv64.json; then \
        echo "FAIL: a manifest key above read an empty value" >&2; \
        exit 1; \
    fi

# Smoke check at build time: Xvfb, GLX and llvmpipe draw, on this hardware.
RUN set -eu; \
    timeout 300 xvfb-run -a -s "-screen 0 64x64x24" rmp-glx-smoke > /tmp/smoke.log 2>&1 \
        || { cat /tmp/smoke.log; echo "FAIL: the GLX smoke check failed" >&2; exit 1; }; \
    cat /tmp/smoke.log; \
    grep -q '^RMP_GLX_SMOKE_OK .*llvmpipe' /tmp/smoke.log; \
    rm -f /tmp/smoke.log; \
    echo "OK: Xvfb, GLX and llvmpipe draw on riscv64"

WORKDIR /work
