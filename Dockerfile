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

# Zig, used ONLY as a C/C++ cross-compiler for the Linux targets, so the shipped
# binary can ask for an older glibc than this image has. See [linux] glibc in
# raylib_multiplatform.toml and tools/linux_build.sh.
ARG ZIG_VERSION=0.16.0
ARG ZIG_SHA256_X86_64=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
ARG ZIG_SHA256_AARCH64=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17
# The glibc the cache is warmed for. It has to match the project's default,
# because warming for the wrong one buys nothing.
ARG ZIG_WARM_GLIBC=2.28

# UPX, for [upx] in the .toml. In the image rather than downloaded per job for
# the reason in the framework's CLAUDE.md: a download that fails on a bad day
# takes the whole pipeline with it, and that is what the image is for.
ARG UPX_VERSION=5.2.0
ARG UPX_SHA256_X86_64=3db5d3294707439db97866feab8d75d800f028f48481a40547411824da4288a1
ARG UPX_SHA256_AARCH64=55d48a61e8ffd17152db871c855376cba7f08e830b37799d0947a16dff8ec36c

# butler, for publishing to itch.io. amd64 only -- broth.itch.zone publishes no
# arm64 build, and the itch job is x64 anyway.
ARG BUTLER_VERSION=15.24.0
ARG BUTLER_SHA256_X86_64=bee1d708b5ed3dc7efcda3b5416ad5ca87a04d7e5fb6ebada510f3ba0cba3b69

# clang-format and clang-tidy for the lint job, from PyPI because that is the
# only place they are published at a pinned patch version -- distro packages
# move. These MUST match clang_format/clang_tidy in the framework's
# thirdparty/FROZEN_VERSIONS.md; versions_check.sh compares them.
ARG CLANG_TOOLS_VERSION=22.1.8

# actionlint, for the lint job. amd64 only, which is what that job runs on.
ARG ACTIONLINT_VERSION=1.7.12
ARG ACTIONLINT_SHA256_X86_64=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8

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
        # Python (emsdk invokes `python`; noble only ships python3).
        # 3.12 gives `tomllib` in the stdlib, which is what tools/configure.py
        # parses raylib_multiplatform.toml with — no pip, nothing downloaded.
        python3 \
        python-is-python3 \
        # Pillow, for generating the Android launcher icons from the single
        # source PNG in the config. The Android job runs entirely inside this
        # container, so there is no host step to escape to, and PNG decoding is
        # not in the stdlib. From the apt snapshot, so it stays frozen.
        python3-pil \
        # pip, for the pinned clang tooling below. The hosted runners have it
        # preinstalled and this image did not, which is why the first attempt
        # died on `pip3: not found` -- a difference that only shows up here.
        python3-pip \
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
        # DRM/KMS: straight to the screen through the kernel, no X11 and no
        # Wayland. The linux-drm job used to apt-get these at job time, which is
        # exactly the download that takes a pipeline down on a bad day.
        libdrm-dev \
        libgbm-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev \
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

# Where the warmed zig cache lives, so tools/linux_build.sh finds it instead of
# rebuilding libc++ on every job. Read-only to the build; zig writes anything
# new under it only if it can, and falls back to the user's own cache if not.
ENV ZIG_GLOBAL_CACHE_DIR=/opt/zig-cache

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
# UPX (pinned + verified)
# ---------------------------------------------------------------------------
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) upx_arch=arm64;  sha="$UPX_SHA256_AARCH64" ;; \
        *)     upx_arch=amd64;  sha="$UPX_SHA256_X86_64"  ;; \
    esac; \
    name="upx-${UPX_VERSION}-${upx_arch}_linux"; \
    curl -fsSL "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/${name}.tar.xz" \
        -o /tmp/upx.tar.xz; \
    echo "${sha}  /tmp/upx.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/upx.tar.xz -C /tmp; \
    mv "/tmp/${name}/upx" /usr/local/bin/upx; \
    chmod +x /usr/local/bin/upx; \
    rm -rf /tmp/upx.tar.xz "/tmp/${name}"; \
    upx --version | head -1

# ---------------------------------------------------------------------------
# actionlint (pinned + verified). amd64 only.
# ---------------------------------------------------------------------------
RUN set -eux; \
    if [ "$TARGETARCH" = "arm64" ]; then \
        echo "actionlint: amd64 only; skipping"; \
    else \
        curl -fsSL \
            "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
            -o /tmp/actionlint.tgz; \
        echo "${ACTIONLINT_SHA256_X86_64}  /tmp/actionlint.tgz" | sha256sum -c -; \
        tar -xzf /tmp/actionlint.tgz -C /usr/local/bin actionlint; \
        chmod +x /usr/local/bin/actionlint; \
        rm /tmp/actionlint.tgz; \
        actionlint --version; \
    fi

# ---------------------------------------------------------------------------
# clang-format / clang-tidy (pinned)
# ---------------------------------------------------------------------------
# Installed with --break-system-packages because this is a build image with one
# Python and no other tenant: a venv here would only add a path for every job to
# remember.
RUN set -eux; \
    python3 -m pip install --no-cache-dir --break-system-packages \
        "clang-format==${CLANG_TOOLS_VERSION}" \
        "clang-tidy==${CLANG_TOOLS_VERSION}"; \
    clang-format --version; \
    clang-tidy --version | head -2

# ---------------------------------------------------------------------------
# butler (pinned + verified). amd64 only.
# ---------------------------------------------------------------------------
RUN set -eux; \
    if [ "$TARGETARCH" = "arm64" ]; then \
        echo "butler: no arm64 build published; skipping"; \
    else \
        curl -fsSL --retry 5 --retry-delay 3 \
            "https://broth.itch.zone/butler/linux-amd64/${BUTLER_VERSION}/archive/default" \
            -o /tmp/butler.zip; \
        echo "${BUTLER_SHA256_X86_64}  /tmp/butler.zip" | sha256sum -c -; \
        unzip -q /tmp/butler.zip -d /opt/butler; \
        chmod +x /opt/butler/butler; \
        ln -s /opt/butler/butler /usr/local/bin/butler; \
        rm /tmp/butler.zip; \
        butler -V; \
    fi

# ---------------------------------------------------------------------------
# Zig (pinned + verified), and its libc++ built ahead of time
# ---------------------------------------------------------------------------
# WHY IT IS IN THE IMAGE. tools/linux_build.sh downloads it otherwise, which
# works but costs ~45 MB on every Linux job.
#
# WHY THE CACHE IS WARMED, which is the larger half: the first time zig c++
# targets a triple it compiles its bundled libc++ from source. That is a minute
# of build time and about 3400 warnings from libc++'s own sources — noise that
# is not about the project and that no flag on our command line can reach,
# because the compilation happens inside zig. Doing it here means the runner
# never sees it.
#
# ZIG_GLOBAL_CACHE_DIR is exported below so the cache built here is the cache
# the build finds.
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) zig_arch=aarch64; sha="$ZIG_SHA256_AARCH64" ;; \
        *)     zig_arch=x86_64;  sha="$ZIG_SHA256_X86_64"  ;; \
    esac; \
    name="zig-${zig_arch}-linux-${ZIG_VERSION}"; \
    curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/${name}.tar.xz" -o /tmp/zig.tar.xz; \
    echo "${sha}  /tmp/zig.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/zig.tar.xz -C /opt; \
    mv "/opt/${name}" /opt/zig; \
    ln -s /opt/zig/zig /usr/local/bin/zig; \
    rm /tmp/zig.tar.xz; \
    zig version; \
    printf '#include <string>\n#include <vector>\nint main(){return 0;}\n' > /tmp/warm.cpp; \
    ZIG_GLOBAL_CACHE_DIR=/opt/zig-cache \
      zig c++ -target "${zig_arch}-linux-gnu.${ZIG_WARM_GLIBC}" -O2 \
      /tmp/warm.cpp -o /tmp/warm 2>/dev/null; \
    /tmp/warm; \
    rm -f /tmp/warm /tmp/warm.cpp; \
    chmod -R a+rX /opt/zig-cache

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
      "  \"zig\": \"${ZIG_VERSION}\"," \
      "  \"upx\": \"${UPX_VERSION}\"," \
      "  \"actionlint\": \"${ACTIONLINT_VERSION}\"," \
      "  \"clang_tools\": \"${CLANG_TOOLS_VERSION}\"," \
      "  \"butler\": \"${BUTLER_VERSION}\"," \
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
# The two Python assertions matter as much as the compilers: tools/configure.py
# needs `tomllib` to read the config at all, and Pillow to produce the Android
# launcher icons. Without them the Android job fails halfway through instead of
# the image failing to build.
RUN cmake --version && ninja --version && zig version && gcc --version | head -1 \
    && aarch64-linux-gnu-gcc --version | head -1 \
    && riscv64-linux-gnu-gcc --version | head -1 \
    && emcc --version | head -1 \
    && java -version 2>&1 | head -1 \
    && python3 -c "import sys, tomllib; print('python', '.'.join(map(str, sys.version_info[:3])), '+ tomllib')" \
    && python3 -c "import PIL; print('pillow', PIL.__version__)"
