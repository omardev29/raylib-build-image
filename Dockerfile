# raylib_multiplatform — CI build image
#
# One image with the full toolchain so CI builds are reproducible and download
# nothing at job time. Built for linux/amd64 and linux/arm64.
#
# EVERYTHING IS PINNED, and "pinned" here means:
#   * the base image by @sha256 digest, not by tag;
#   * every apt package by an Ubuntu *snapshot* timestamp, so `apt-get install`
#     resolves to the same bytes today and in two years;
#   * every downloaded tarball/zip verified against a hard-coded sha256;
#   * emsdk by commit SHA, not by tag (tags are movable).
#
# Bump a version deliberately, never by accident. When you bump anything here,
# bump the matching row in the template's thirdparty/FROZEN_VERSIONS.md —
# tools/versions_check.sh fails CI if the two drift apart.
#
#   docker build -t raylib-build .

# ---------------------------------------------------------------------------
# Base image, pinned by digest. This is `ubuntu:24.04` as of 2026-08-10.
# ARG-before-FROM is the only way to parameterise the base image.
# ---------------------------------------------------------------------------
ARG UBUNTU_DIGEST=sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea
FROM ubuntu:24.04@${UBUNTU_DIGEST}

# ---------------------------------------------------------------------------
# Pinned versions (single place to bump). ARG, not ENV: overridable with
# --build-arg, and they do not leak into the runtime environment of every
# downstream CI job. Only the handful of values that tools actually read at
# runtime are re-exported as ENV further down.
# ---------------------------------------------------------------------------
ARG TARGETARCH

# Ubuntu archive snapshot. https://snapshot.ubuntu.com serves the archive AND
# the ports (arm64/riscv64) content from a single host, so one set of sources
# covers every architecture we build for.
ARG APT_SNAPSHOT=20260801T000000Z

ARG CMAKE_VERSION=3.30.3
ARG CMAKE_SHA256_X86_64=4a5864e9ff0d7945731fe6d14afb61490bf0ec154527bc3af0456bd8fa90decb
ARG CMAKE_SHA256_AARCH64=420f17c58de4ed8b53c1055a34318aec5c06d94b04dac9dd3c72861dfdc99d52

ARG NINJA_VERSION=1.12.1
ARG NINJA_SHA256_X86_64=6f98805688d19672bd699fbbfa2c2cf0fc054ac3df1f0e6a47664d963d530255
ARG NINJA_SHA256_AARCH64=5c25c6570b0155e95fce5918cb95f1ad9870df5768653afe128db822301a05a1

# emsdk pinned by COMMIT, not by tag: `--branch <sha>` is not a thing (git only
# accepts refs there), so the install below fetches the commit explicitly.
# ca7b40ae = tag 3.1.61.
ARG EMSDK_COMMIT=ca7b40ae222a2d8763b6ac845388744b0e57cfb7
ARG EMSCRIPTEN_VERSION=3.1.61

# Android. platform 36 = Android 16, required by Google Play for every upload
# from 2026-08-31. NDK r28 aligns ELF segments to 16 KB by default, which Play
# also requires. cmake 3.31.6 is installed *into the SDK* so Gradle's
# externalNativeBuild resolves it there instead of accidentally binding to
# whatever /opt/cmake happens to be.
ARG ANDROID_CMDLINE_TOOLS=15859902
ARG ANDROID_CMDLINE_TOOLS_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_NDK_VERSION=28.2.13676358
ARG ANDROID_SDK_CMAKE=3.31.6

ENV ANDROID_HOME=/opt/android-sdk \
    EMSDK_HOME=/opt/emsdk \
    DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Freeze apt to a snapshot timestamp.
#
# Two things worth knowing before you touch this block:
#   1. snapshot.ubuntu.com is HTTPS-only (plain http 301s), so apt needs
#      ca-certificates before it can reach it. The base image may or may not
#      ship them, hence the one-package bootstrap against the default sources.
#      ca-certificates is re-resolved from the snapshot in the main install
#      below, so the version that survives into the image is the pinned one.
#   2. The rewrite is UNCONDITIONAL. It used to be gated on amd64, with arm64
#      left on ports.ubuntu.com — do that here and the arm64 variant ends up
#      with no repositories at all.
# ---------------------------------------------------------------------------
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
    # A frozen snapshot eventually looks "expired" to apt: the noble Release
    # file is dated 2024-04-25 and never moves again.
    printf '%s\n' 'Acquire::Check-Valid-Until "false";' \
        > /etc/apt/apt.conf.d/99no-check-valid-until; \
    apt-get update

# ---------------------------------------------------------------------------
# Base packages: compilers, raylib desktop deps, cross toolchains, qemu, misc
# ---------------------------------------------------------------------------
RUN apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        g++ \
        clang \
        git \
        ca-certificates \
        curl \
        wget \
        unzip \
        zip \
        xz-utils \
        ccache \
        pkg-config \
        # Python (emsdk invokes `python`; noble only ships python3)
        python3 \
        python-is-python3 \
        # raylib desktop runtime/build deps (X11 + GL)
        libx11-dev \
        libxrandr-dev \
        libxi-dev \
        libxcursor-dev \
        libxinerama-dev \
        libgl1-mesa-dev \
        libwayland-dev \
        libxkbcommon-dev \
        wayland-protocols \
        extra-cmake-modules \
        # Headless X server + Mesa software GL for the CI runtime smoke tests
        # (runs the game with no physical display; llvmpipe renders in software).
        xvfb \
        libgl1-mesa-dri \
        # Cross toolchains (Linux ARM64 + RISC-V) + qemu for running foreign bins
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        gcc-riscv64-linux-gnu \
        g++-riscv64-linux-gnu \
        qemu-user-static \
        # JDK for Android builds
        openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# RISC-V cross-build support (amd64 only): riscv64 X11/GL dev libraries.
# The snapshot host carries every architecture, so unlike the old ports.ubuntu
# split this needs nothing but `dpkg --add-architecture`.
# ---------------------------------------------------------------------------
RUN if [ "$TARGETARCH" = "amd64" ]; then set -eux; \
        dpkg --add-architecture riscv64; \
        apt-get update; \
        # RISC-V is a first-class target: install its X11/GL stack and FAIL the
        # build if it is not present (no silent degradation).
        apt-get install -y --no-install-recommends \
            libc6:riscv64 libbsd0:riscv64 libzstd1:riscv64 zlib1g:riscv64 \
            libicu74:riscv64 libedit2:riscv64 libelf1t64:riscv64 libxml2:riscv64 \
            libx11-dev:riscv64 libxrandr-dev:riscv64 libxi-dev:riscv64 \
            libxcursor-dev:riscv64 libxinerama-dev:riscv64 libgl1-mesa-dev:riscv64; \
        dpkg-query -W -f='${Status}\n' libx11-dev:riscv64 | grep -q "install ok installed"; \
        dpkg-query -W -f='${Status}\n' libgl1-mesa-dev:riscv64 | grep -q "install ok installed"; \
        echo "OK: riscv64 multiarch X11/GL libs installed"; \
        rm -rf /var/lib/apt/lists/*; \
    fi

# ---------------------------------------------------------------------------
# CMake (pinned + verified; replaces distro version)
# ---------------------------------------------------------------------------
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) arch=aarch64; sha="$CMAKE_SHA256_AARCH64" ;; \
        *)     arch=x86_64;  sha="$CMAKE_SHA256_X86_64"  ;; \
    esac; \
    curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${arch}.tar.gz" \
        -o /tmp/cmake.tar.gz; \
    echo "${sha}  /tmp/cmake.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/cmake.tar.gz -C /opt; \
    ln -s "/opt/cmake-${CMAKE_VERSION}-linux-${arch}" /opt/cmake; \
    rm /tmp/cmake.tar.gz
ENV PATH=/opt/cmake/bin:$PATH

# ---------------------------------------------------------------------------
# Ninja (pinned + verified)
# ---------------------------------------------------------------------------
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) ninja_asset=ninja-linux-aarch64.zip; sha="$NINJA_SHA256_AARCH64" ;; \
        *)     ninja_asset=ninja-linux.zip;         sha="$NINJA_SHA256_X86_64"  ;; \
    esac; \
    curl -fsSL "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/${ninja_asset}" \
        -o /tmp/ninja.zip; \
    echo "${sha}  /tmp/ninja.zip" | sha256sum -c -; \
    unzip /tmp/ninja.zip -d /usr/local/bin; \
    chmod +x /usr/local/bin/ninja; \
    rm /tmp/ninja.zip; \
    ninja --version

# ---------------------------------------------------------------------------
# Emscripten (Web). Installed for both amd64 and arm64.
#
# Fetched by commit: `git clone --depth 1 --branch <sha>` does NOT work, git
# only accepts refs for --branch. init + fetch <sha> + checkout FETCH_HEAD is
# the shallow-clone-a-commit idiom.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p ${EMSDK_HOME}; \
    cd ${EMSDK_HOME}; \
    git init -q .; \
    git remote add origin https://github.com/emscripten-core/emsdk.git; \
    git fetch --depth 1 origin ${EMSDK_COMMIT}; \
    git checkout -q FETCH_HEAD; \
    ./emsdk install ${EMSCRIPTEN_VERSION}; \
    ./emsdk activate ${EMSCRIPTEN_VERSION}; \
    ${EMSDK_HOME}/upstream/emscripten/emcc --version
ENV EMSDK=${EMSDK_HOME} \
    PATH=${EMSDK_HOME}:${EMSDK_HOME}/upstream/emscripten:$PATH

# ---------------------------------------------------------------------------
# Android SDK/NDK. NDK host binaries are x86_64-only, so skip on arm64.
# ---------------------------------------------------------------------------
RUN if [ "$TARGETARCH" = "amd64" ]; then set -eux; \
        curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS}_latest.zip" \
            -o /tmp/cmdtools.zip; \
        echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/cmdtools.zip" | sha256sum -c -; \
        mkdir -p ${ANDROID_HOME}/cmdline-tools; \
        unzip -q /tmp/cmdtools.zip -d ${ANDROID_HOME}/cmdline-tools; \
        mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest; \
        rm /tmp/cmdtools.zip; \
        yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null; \
        ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
            "platform-tools" \
            "platforms;${ANDROID_PLATFORM}" \
            "build-tools;${ANDROID_BUILD_TOOLS}" \
            "ndk;${ANDROID_NDK_VERSION}" \
            "cmake;${ANDROID_SDK_CMAKE}"; \
        # Fail the image build, not the CI job, if a package silently did not land.
        test -d "${ANDROID_HOME}/platforms/${ANDROID_PLATFORM}"; \
        test -d "${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS}"; \
        test -d "${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}"; \
        test -x "${ANDROID_HOME}/cmake/${ANDROID_SDK_CMAKE}/bin/cmake"; \
        echo "OK: Android SDK ${ANDROID_PLATFORM} / NDK ${ANDROID_NDK_VERSION} installed"; \
    else \
        echo "Skipping Android SDK on ${TARGETARCH} (NDK host is x86_64-only)"; \
    fi

ENV ANDROID_SDK_ROOT=${ANDROID_HOME} \
    ANDROID_NDK_VERSION=${ANDROID_NDK_VERSION} \
    ANDROID_NDK_HOME=${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION} \
    ANDROID_NDK_ROOT=${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}
ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:$PATH

# ---------------------------------------------------------------------------
# Build manifest. Every containerised CI job cats this as its first step, so a
# failing log always says exactly which toolchain produced it. It is also what
# the template's tools/versions_check.sh compares against.
# ---------------------------------------------------------------------------
RUN set -eux; \
    printf '%s\n' \
      '{' \
      "  \"arch\": \"${TARGETARCH}\"," \
      "  \"apt_snapshot\": \"${APT_SNAPSHOT}\"," \
      "  \"ubuntu\": \"24.04\"," \
      "  \"cmake\": \"${CMAKE_VERSION}\"," \
      "  \"ninja\": \"${NINJA_VERSION}\"," \
      "  \"emscripten\": \"${EMSCRIPTEN_VERSION}\"," \
      "  \"emsdk_commit\": \"${EMSDK_COMMIT}\"," \
      "  \"android_cmdline_tools\": \"${ANDROID_CMDLINE_TOOLS}\"," \
      "  \"android_platform\": \"${ANDROID_PLATFORM}\"," \
      "  \"android_build_tools\": \"${ANDROID_BUILD_TOOLS}\"," \
      "  \"android_ndk\": \"${ANDROID_NDK_VERSION}\"," \
      "  \"android_sdk_cmake\": \"${ANDROID_SDK_CMAKE}\"" \
      '}' \
      > /etc/raylib-build-image.json; \
    cat /etc/raylib-build-image.json

WORKDIR /work

# Smoke check so a broken image fails at build time, not at CI time.
RUN cmake --version && ninja --version && gcc --version | head -1 \
    && aarch64-linux-gnu-gcc --version | head -1 \
    && riscv64-linux-gnu-gcc --version | head -1 \
    && emcc --version | head -1 \
    && java -version 2>&1 | head -1
