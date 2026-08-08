# raylib_cmake_template — CI build image
#
# One image with the full toolchain so CI builds are reproducible and download
# nothing at job time. Built for linux/amd64 and linux/arm64.
#
# Everything is PINNED. Bump a version deliberately, never by accident.
#
#   docker build -t raylib-build .

FROM ubuntu:24.04

# ---------------------------------------------------------------------------
# Pinned versions (single place to bump)
# ---------------------------------------------------------------------------
ARG TARGETARCH
ENV CMAKE_VERSION=3.30.3 \
    NINJA_VERSION=1.12.1 \
    EMSDK_TAG=3.1.61 \
    EMSCRIPTEN_VERSION=3.1.61 \
    ANDROID_CMDLINE_TOOLS=11076708 \
    ANDROID_PLATFORM=android-34 \
    ANDROID_BUILD_TOOLS=34.0.0 \
    ANDROID_NDK=26.1.10909125 \
    ANDROID_HOME=/opt/android-sdk \
    EMSDK_HOME=/opt/emsdk \
    DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Base packages: compilers, raylib desktop deps, cross toolchains, qemu, misc
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
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
        # Headless X server for the CI runtime smoke tests (runs the game with
        # no physical display; Mesa provides software GL).
        xvfb \
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
# RISC-V cross-build support (amd64 only): riscv64 X11/GL dev libraries via
# Ubuntu ports, so raylib can be cross-compiled for riscv64-linux-gnu.
# ---------------------------------------------------------------------------
RUN if [ "$TARGETARCH" = "amd64" ]; then set -eux; \
        # riscv64 packages only exist on ports.ubuntu.com. Rewrite the apt
        # sources as explicit per-architecture entries (amd64 from
        # archive/security, riscv64 from ports). Using a clean, arch-qualified
        # sources.list is more reliable for multiarch than pinning the deb822
        # ubuntu.sources in place, which made apt's resolver re-break essential
        # native packages (dpkg/apt/util-linux).
        rm -f /etc/apt/sources.list.d/ubuntu.sources; \
        printf '%s\n' \
            'deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main universe restricted multiverse' \
            'deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-updates main universe restricted multiverse' \
            'deb [arch=amd64] http://security.ubuntu.com/ubuntu noble-security main universe restricted multiverse' \
            'deb [arch=riscv64] http://ports.ubuntu.com/ubuntu-ports noble main universe' \
            'deb [arch=riscv64] http://ports.ubuntu.com/ubuntu-ports noble-updates main universe' \
            > /etc/apt/sources.list; \
        dpkg --add-architecture riscv64; \
        apt-get update; \
        # RISC-V is a first-class target: install its X11/GL stack and FAIL the
        # build if it is not present (no silent degradation).
        apt-get install -y --no-install-recommends \
            libc6:riscv64 libbsd0:riscv64 libzstd1:riscv64 zlib1g:riscv64 \
            libicu74:riscv64 libedit2:riscv64 libelf1t64:riscv64 libxml2:riscv64 \
            libx11-dev:riscv64 libxrandr-dev:riscv64 libxi-dev:riscv64 \
            libxcursor-dev:riscv64 libxinerama-dev:riscv64 libgl1-mesa-dev:riscv64; \
        # Verify the riscv64 X11/GL dev stack is really installed.
        dpkg-query -W -f='${Status}\n' libx11-dev:riscv64 | grep -q "install ok installed"; \
        dpkg-query -W -f='${Status}\n' libgl1-mesa-dev:riscv64 | grep -q "install ok installed"; \
        echo "OK: riscv64 multiarch X11/GL libs installed"; \
        rm -rf /var/lib/apt/lists/*; \
    fi

# ---------------------------------------------------------------------------
# CMake (pinned; replaces distro version)
# ---------------------------------------------------------------------------
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) arch=aarch64 ;; \
        *)     arch=x86_64 ;; \
    esac; \
    curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${arch}.tar.gz" \
        -o /tmp/cmake.tar.gz; \
    tar -xzf /tmp/cmake.tar.gz -C /opt; \
    ln -s "/opt/cmake-${CMAKE_VERSION}-linux-${arch}" /opt/cmake; \
    rm /tmp/cmake.tar.gz
ENV PATH=/opt/cmake/bin:$PATH

# ---------------------------------------------------------------------------
# Ninja (pinned)
# ---------------------------------------------------------------------------
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) ninja_asset=ninja-linux-aarch64.zip ;; \
        *)     ninja_asset=ninja-linux.zip ;; \
    esac; \
    curl -fsSL "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/${ninja_asset}" \
        -o /tmp/ninja.zip; \
    unzip /tmp/ninja.zip -d /usr/local/bin; \
    chmod +x /usr/local/bin/ninja; \
    rm /tmp/ninja.zip; \
    ninja --version

# ---------------------------------------------------------------------------
# Emscripten (Web). Installed for both amd64 and arm64.
# ---------------------------------------------------------------------------
RUN git clone --depth 1 --branch ${EMSDK_TAG} https://github.com/emscripten-core/emsdk.git ${EMSDK_HOME} \
    && cd ${EMSDK_HOME} \
    && ./emsdk install ${EMSCRIPTEN_VERSION} \
    && ./emsdk activate ${EMSCRIPTEN_VERSION} \
    && ${EMSDK_HOME}/upstream/emscripten/emcc --version
ENV EMSDK=${EMSDK_HOME} \
    PATH=${EMSDK_HOME}:${EMSDK_HOME}/upstream/emscripten:$PATH

# ---------------------------------------------------------------------------
# Android SDK/NDK. NDK host binaries are x86_64-only, so skip on arm64.
# ---------------------------------------------------------------------------
RUN if [ "$TARGETARCH" = "amd64" ]; then set -eux; \
        curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS}_latest.zip" \
            -o /tmp/cmdtools.zip; \
        mkdir -p ${ANDROID_HOME}/cmdline-tools; \
        unzip -q /tmp/cmdtools.zip -d ${ANDROID_HOME}/cmdline-tools; \
        mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest; \
        rm /tmp/cmdtools.zip; \
        yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null; \
        ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
            "platform-tools" \
            "platforms;${ANDROID_PLATFORM}" \
            "build-tools;${ANDROID_BUILD_TOOLS}" \
            "ndk;${ANDROID_NDK}"; \
    else \
        echo "Skipping Android SDK on ${TARGETARCH} (NDK host is x86_64-only)"; \
    fi
ENV ANDROID_NDK_HOME=${ANDROID_HOME}/ndk/${ANDROID_NDK} \
    ANDROID_NDK_ROOT=${ANDROID_HOME}/ndk/${ANDROID_NDK}
ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:$PATH

# ---------------------------------------------------------------------------
# Non-root user (GitHub container jobs run as root by default; keep it simple)
# ---------------------------------------------------------------------------
RUN useradd -m -s /bin/bash builder || true
WORKDIR /work

# Smoke check so a broken image fails at build time, not at CI time.
RUN cmake --version && ninja --version && gcc --version | head -1 \
    && aarch64-linux-gnu-gcc --version | head -1 \
    && riscv64-linux-gnu-gcc --version | head -1 \
    && emcc --version | head -1
