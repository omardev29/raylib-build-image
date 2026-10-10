# raylib_multiplatform — CI build image
#
# One image with the full toolchain so CI builds are reproducible and download
# nothing at job time. Built for linux/amd64 and linux/arm64.
#
# EVERYTHING IS PINNED, and "pinned" here means:
#   * the base image by @sha256 digest, not by tag;
#   * every apt package by an Ubuntu *snapshot* timestamp, so `apt-get install`
#     resolves to the same bytes today and in two years;
#   * every downloaded tarball/zip/.deb verified against a hard-coded sha256;
#   * every Python package by version AND by the sha256 of its wheel
#     (python/requirements-ci.txt, installed with --require-hashes);
#   * emsdk by commit SHA, not by tag (tags are movable), and the Gradle home
#     warmed from a framework commit SHA.
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

# Mull, mutation testing for C and C++. It is a clang pass plugin, so it is
# built per LLVM release and has to be the one for the clang this image
# compiles with: noble's clang is 18.1.3, and so are the llvm-18 and
# libclang-rt-18-dev the apt list installs. The install step refuses a Mull
# built for any other LLVM.
ARG MULL_VERSION=0.34.1
ARG MULL_LLVM_VERSION=18.1.3
ARG MULL_SHA256_X86_64=983ea9c84ecab621414d5442a66c1a1ce4127491b79d42fd5e2fd6fe01d02699
ARG MULL_SHA256_AARCH64=598d17a5b5304f5eae7492bd4269e9f5a57dcffc1c4a40af75336c9a8a1ef5ad

# The raylib_multiplatform commit whose Android build warms the Gradle home
# (amd64 only; see the Gradle section). A full SHA, for the same reason emsdk is
# pinned by one. Bump it when raymob's Gradle, AGP or dependencies change.
ARG GRADLE_WARM_COMMIT=259e1b349dfbb7a7c2e93523e6605656aefec458

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
        # The rest of LLVM 18, for the clang above. Without it that clang
        # compiles -fsanitize=address, -fsanitize=fuzzer and
        # -fprofile-instr-generate and then cannot LINK them ("cannot find
        # .../libclang_rt.profile-x86_64.a"), and there is no llvm-cov or
        # llvm-profdata to read a profile with. All three at the clang's own
        # version, 18.1.3, from the same snapshot:
        #   llvm-18            llvm-cov-18, llvm-profdata-18, llvm-cxxfilt-18,
        #                      llvm-symbolizer-18 (readable sanitizer stacks)
        #   llvm               the unversioned names, so scripts say llvm-cov
        #   libclang-rt-18-dev compiler-rt: the asan, ubsan, lsan, fuzzer and
        #                      profile runtimes
        llvm-18 \
        llvm \
        libclang-rt-18-dev \
        # cppcheck, the second static analyser next to clang-tidy's. Its
        # Depends pull in Debian's python3-pygments, which is why
        # python/requirements-ci.in pins Pygments to that exact version.
        cppcheck \
        git \
        ca-certificates \
        curl \
        wget \
        unzip \
        zip \
        xz-utils \
        ccache \
        pkg-config \
        # shellcheck, and it is NOT optional decoration: actionlint has no
        # shell analysis of its own. Everything it reports about a `run:` block
        # comes from shelling out to this binary, and when it is missing the
        # whole rule turns itself off -- `-verbose` says
        #   Rule "shellcheck" was disabled: exec: "shellcheck": ... not in $PATH
        # and actionlint then exits 0 on a script full of problems. Verified
        # both ways with a fixture workflow: SC2086 reported with the binary
        # present, "Found total 0 errors" with it removed.
        # The hosted runners ship shellcheck preinstalled, so this worked while
        # the lint job ran on a bare runner and went quiet when it moved into
        # this image -- silently, because a disabled rule looks like a clean one.
        shellcheck \
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
        # PyYAML, for the framework's tools/workflow_check.sh: it parses every
        # workflow to prove each reusable-workflow call grants the permissions
        # its callee declares. Without it that gate printed "skip" and went
        # green, which is how a run with zero jobs and no logs gets shipped.
        # From the apt snapshot, so it stays frozen like everything else.
        python3-yaml \
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
        # xauth is only a *Recommends* of xvfb, and everything here is installed
        # with --no-install-recommends: without it `xvfb-run` dies on
        # "xauth: command not found" and both Linux render jobs fail twenty
        # minutes in. Named explicitly so package resolution cannot drop it.
        xauth \
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
# Mull (pinned + verified), both architectures
# ---------------------------------------------------------------------------
# Installed with apt rather than dpkg, so its Depends (libllvm18,
# libclang-cpp18) resolve from the same snapshot as everything else. Gives
# mull-runner-18 and the clang plugin /usr/lib/mull-ir-frontend-18.
#
# The plugin is loaded INTO clang, so an LLVM mismatch is not a warning, it is
# a plugin that fails to load or misbehaves. Hence the assertion: the LLVM this
# .deb was built for, the LLVM apt installed and the clang on PATH must be one
# version.
RUN set -eux; \
    case "$TARGETARCH" in \
        arm64) mull_arch=aarch64; sha="$MULL_SHA256_AARCH64" ;; \
        *)     mull_arch=amd64;   sha="$MULL_SHA256_X86_64"  ;; \
    esac; \
    curl -fsSL \
        "https://github.com/mull-project/mull/releases/download/${MULL_VERSION}/Mull-18-${MULL_VERSION}-LLVM-${MULL_LLVM_VERSION}-ubuntu-${mull_arch}-24.04.deb" \
        -o /tmp/mull.deb; \
    echo "${sha}  /tmp/mull.deb" | sha256sum -c -; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/mull.deb; \
    rm -rf /tmp/mull.deb /var/lib/apt/lists/*; \
    test "$(llvm-config-18 --version)" = "${MULL_LLVM_VERSION}"; \
    clang --version | grep -q "clang version ${MULL_LLVM_VERSION} "; \
    mull-runner-18 --version | grep -q "LLVM: ${MULL_LLVM_VERSION}"; \
    test -f /usr/lib/mull-ir-frontend-18

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
# Python test tools (locked + hashed): Hypothesis, mutmut, pytest
# ---------------------------------------------------------------------------
# From python/requirements-ci.txt, a lock with every dependency pinned and the
# sha256 of every wheel it may install (see python/lock.py). --require-hashes
# makes a missing pin or a changed file a failed build; --only-binary=:all:
# means nothing is compiled here, so what is installed is what was hashed.
#
# PyYAML and Pygments are in the lock at the versions apt installed, and pip
# finds them already satisfied and leaves Debian's copies alone. The assertion
# after the install is what proves it: both still import from
# /usr/lib/python3/dist-packages, where apt put them.
COPY python/requirements-ci.txt /usr/local/share/raylib-build-image/requirements-ci.txt
RUN set -eux; \
    python3 -m pip install --no-cache-dir --break-system-packages \
        --require-hashes --only-binary=:all: \
        -r /usr/local/share/raylib-build-image/requirements-ci.txt; \
    python3 -c "import yaml, pygments; \
assert yaml.__file__.startswith('/usr/lib/python3/dist-packages/'), yaml.__file__; \
assert pygments.__file__.startswith('/usr/lib/python3/dist-packages/'), pygments.__file__"; \
    python3 -m pip check

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
# Gradle home, warmed for an --offline Android build (amd64 only)
# ---------------------------------------------------------------------------
# WHY IT EXISTS. Every Android job used to download Gradle and every Maven
# dependency, ~6.5 minutes of it per run. _android.yml cached ~/.gradle, but in
# a container job that is /github/home while Java's user.home is /root, so the
# cache never held anything and was never saved (run 37247019962: "Path
# Validation Error ... no cache is being saved"). A download at job time is the
# thing this image exists to remove. GRADLE_USER_HOME points every user at the
# same place -- the job's root, and dev_shell.sh's --user $(id -u), which is
# why it is world-writable.
#
# HOW IT IS WARMED. The framework is fetched at GRADLE_WARM_COMMIT and built
# the way _android.yml builds it: configure.py --require-icons, a throwaway
# keystore, assembleDebug, then bundleRelease, each a --no-daemon build of its
# own. Twice: with AdMob on and with it off, because without
# play-services-ads, dependency resolution can settle on other androidx
# versions. Then the wrapper's 138 MB zip and the daemon logs go -- the
# unpacked distribution is what runs -- and BOTH variants are built again with
# --offline from a clean tree. Anything missing fails the image build here,
# not the first Android job after the bump.
#
# rmp-keep-cache.gradle turns Gradle's cache cleanup off. Without it, a
# --no-daemon build deletes what it has not touched for 30 days, so a month
# after publishing, an assembleDebug deletes the release-only artifacts and the
# bundleRelease --offline after it fails. Seen, not supposed: with the clock
# faked 60 days ahead (faketime) and the default cleanup, assembleDebug passed
# and bundleRelease --offline died in lintVitalAnalyzeRelease with "Could not
# download lint-gradle-31.13.2.jar ... No cached version available for offline
# mode"; the same two builds with this file both pass.
#
# rmp-warm.properties says what was warmed -- gradle, agp, play_services_ads and
# warm_commit, read from the clone with the regexes the framework's
# versions_check.sh uses -- and the manifest copies it. A game that adds a
# Gradle dependency of its own is not covered and fails --offline loudly.
#
# arm64 has no Android SDK (see above), so there the Gradle home is an empty,
# writable directory: the variable never points at nothing.
ENV GRADLE_USER_HOME=/opt/gradle-home
RUN set -eux; \
    mkdir -p "$GRADLE_USER_HOME"; \
    if [ "$TARGETARCH" = "amd64" ]; then \
        mkdir -p "$GRADLE_USER_HOME/init.d"; \
        printf '%s\n' \
            '// From the raylib-build image: this Gradle home is warmed for' \
            '// --offline builds, and cleanup would delete what one build did not' \
            '// touch for 30 days -- which --offline cannot download back.' \
            'beforeSettings { settings ->' \
            '    settings.caches {' \
            '        cleanup = Cleanup.DISABLED' \
            '    }' \
            '}' \
            > "$GRADLE_USER_HOME/init.d/rmp-keep-cache.gradle"; \
        src=/tmp/rmp-warm; \
        git init -q "$src"; \
        git -C "$src" remote add origin https://github.com/omardev29/raylib_multiplatform.git; \
        git -C "$src" fetch -q --depth 1 origin "$GRADLE_WARM_COMMIT"; \
        git -C "$src" checkout -q FETCH_HEAD; \
        export ANDROID_KEYSTORE_FILE="$src/raymob/release.keystore" \
               ANDROID_KEYSTORE_PASSWORD=ci-throwaway \
               ANDROID_KEY_ALIAS=ci-throwaway \
               ANDROID_KEY_PASSWORD=ci-throwaway; \
        android_build() { \
            admob="$1"; shift; \
            git -C "$src" clean -fdxq; \
            git -C "$src" checkout -q -- .; \
            (cd "$src" && python3 tools/configure.py --require-icons); \
            sed -i "s/^admob\.enabled=.*/admob.enabled=${admob}/" "$src/raymob/generated.properties"; \
            grep -qx "admob.enabled=${admob}" "$src/raymob/generated.properties"; \
            keytool -genkeypair \
                -keystore "$ANDROID_KEYSTORE_FILE" -storetype PKCS12 \
                -alias ci-throwaway -keyalg RSA -keysize 2048 -validity 3650 \
                -storepass ci-throwaway -keypass ci-throwaway \
                -dname "CN=CI THROWAWAY NOT FOR PLAY, OU=CI, O=raylib-template, C=ZZ"; \
            (cd "$src/raymob" && ./gradlew "$@" assembleDebug --no-daemon); \
            (cd "$src/raymob" && ./gradlew "$@" bundleRelease --no-daemon); \
            test -n "$(find "$src/raymob/app/build/outputs/apk/debug" -name '*.apk')"; \
            test -n "$(find "$src/raymob/app/build/outputs/bundle/release" -name '*.aab')"; \
            git -C "$src" diff --exit-code; \
        }; \
        android_build true; \
        android_build false; \
        rm -f "$GRADLE_USER_HOME"/wrapper/dists/gradle-*-bin/*/gradle-*-bin.zip; \
        rm -rf "$GRADLE_USER_HOME/daemon"; \
        android_build true --offline; \
        android_build false --offline; \
        gradle_version="$(sed -nE 's#.*/gradle-([0-9.]+)-bin\.zip.*#\1#p' "$src/raymob/gradle/wrapper/gradle-wrapper.properties" | head -1)"; \
        agp_version="$(sed -nE "s/.*com\.android\.application' version '([^']+)'.*/\1/p" "$src/raymob/build.gradle" | head -1)"; \
        ads_version="$(sed -nE "s/.*play-services-ads:([0-9.]+)'.*/\1/p" "$src/raymob/app/build.gradle" | head -1)"; \
        test -n "$gradle_version"; \
        test -n "$agp_version"; \
        test -n "$ads_version"; \
        ls "$GRADLE_USER_HOME/wrapper/dists/gradle-${gradle_version}-bin/"*"/gradle-${gradle_version}/bin/gradle"; \
        printf '%s\n' \
            "# What this Gradle home was warmed with. Written by the raylib-build image." \
            "gradle=${gradle_version}" \
            "agp=${agp_version}" \
            "play_services_ads=${ads_version}" \
            "warm_commit=${GRADLE_WARM_COMMIT}" \
            > "$GRADLE_USER_HOME/rmp-warm.properties"; \
        rm -rf "$src" "$GRADLE_USER_HOME/daemon" "$GRADLE_USER_HOME/caches/build-cache-1"; \
        # AGP's per-user leftovers from the warm-up: a debug signing key and an
        # analytics opt-in. Neither belongs in an image; CI's HOME is
        # /github/home, where AGP makes its own.
        rm -f /root/.android/debug.keystore /root/.android/debug.keystore.lock \
              /root/.android/analytics.settings; \
        cat "$GRADLE_USER_HOME/rmp-warm.properties"; \
    else \
        echo "Gradle home: amd64 only (no Android SDK on ${TARGETARCH}); left empty"; \
    fi; \
    chmod -R a+rwX "$GRADLE_USER_HOME"; \
    du -sh "$GRADLE_USER_HOME"

# ---------------------------------------------------------------------------
# Build manifest. Every containerised CI job cats this as its first step, so a
# failing log always says exactly which toolchain produced it. It is also what
# the template's tools/versions_check.sh compares against.
#
# The keys for what came from apt or pip -- llvm, cppcheck, mull, hypothesis,
# mutmut, pytest -- are read from the installed tool, not copied from an ARG,
# so the manifest says what IS in the image. The Gradle keys exist on amd64
# only, copied from rmp-warm.properties; on arm64 they are absent rather than
# faked. Every value must be non-empty (a version that read nothing is a
# broken image, not an unknown one) and the file must parse as JSON.
# ---------------------------------------------------------------------------
RUN set -eux; \
    kv() { printf '  "%s": "%s",\n' "$1" "$2"; }; \
    pyver() { python3 -c 'import importlib.metadata, sys; print(importlib.metadata.version(sys.argv[1]))' "$1"; }; \
    warm() { sed -nE "s/^$1=(.*)$/\1/p" "$GRADLE_USER_HOME/rmp-warm.properties"; }; \
    { \
      echo '{'; \
      kv arch                  "${TARGETARCH}"; \
      kv apt_snapshot          "${APT_SNAPSHOT}"; \
      kv ubuntu                "24.04"; \
      kv cmake                 "${CMAKE_VERSION}"; \
      kv zig                   "${ZIG_VERSION}"; \
      kv zig_warm_glibc        "${ZIG_WARM_GLIBC}"; \
      kv upx                   "${UPX_VERSION}"; \
      kv actionlint            "${ACTIONLINT_VERSION}"; \
      kv clang_tools           "${CLANG_TOOLS_VERSION}"; \
      kv butler                "${BUTLER_VERSION}"; \
      kv ninja                 "${NINJA_VERSION}"; \
      kv emscripten            "${EMSCRIPTEN_VERSION}"; \
      kv emsdk_commit          "${EMSDK_COMMIT}"; \
      kv llvm                  "$(llvm-config-18 --version)"; \
      kv cppcheck              "$(cppcheck --version | sed -nE 's/^Cppcheck ([0-9.]+)$/\1/p')"; \
      kv mull                  "$(mull-runner-18 --version | sed -nE 's/^mull-runner ([0-9.]+)$/\1/p')"; \
      kv hypothesis            "$(pyver hypothesis)"; \
      kv mutmut                "$(pyver mutmut)"; \
      kv pytest                "$(pyver pytest)"; \
      if [ "$TARGETARCH" = "amd64" ]; then \
        kv gradle              "$(warm gradle)"; \
        kv agp                 "$(warm agp)"; \
        kv play_services_ads   "$(warm play_services_ads)"; \
        kv gradle_warm_commit  "$(warm warm_commit)"; \
      fi; \
      kv android_cmdline_tools "${ANDROID_CMDLINE_TOOLS}"; \
      kv android_platform      "${ANDROID_PLATFORM}"; \
      kv android_build_tools   "${ANDROID_BUILD_TOOLS}"; \
      kv android_ndk           "${ANDROID_NDK_VERSION}"; \
      printf '  "%s": "%s"\n' android_sdk_cmake "${ANDROID_SDK_CMAKE}"; \
      echo '}'; \
    } > /etc/raylib-build-image.json; \
    cat /etc/raylib-build-image.json; \
    python3 -m json.tool /etc/raylib-build-image.json > /dev/null; \
    if grep -n '": ""' /etc/raylib-build-image.json; then \
        echo "FAIL: a manifest key above read an empty version" >&2; \
        exit 1; \
    fi

WORKDIR /work

# Smoke check so a broken image fails at build time, not at CI time.
#
# The rule is: every tool a CI job invokes gets invoked HERE, because the
# alternative is finding out twenty minutes into a matrix, on a change that
# touched game code. This list used to be compilers only, so it never exercised
# `xvfb-run` (both Linux render jobs), `objdump` (glibc_check.sh and three
# static gates), `upx`, `zip`, `pkg-config`, or clang-format/clang-tidy (the
# whole lint job) -- all installed, none of them ever proven to run.
#
# WHY THE `check` HELPER AND NOT `tool --version | head -1`. A pipe throws the
# exit status away: /bin/sh on noble is dash, which has no `set -o pipefail`, so
# `zip -v | head -1` exits 0 even when zip is not installed at all -- it prints
# "not found" and the build goes green. That is the same shape as the
# RAY_TEST_BOOT_OK bug in the framework's CLAUDE.md: a marker that only ever
# prints is not a gate. `check` runs the command, keeps its exit status, and
# only then trims the output for the log. (Reaching for `set -o pipefail`
# instead would trade this bug for SIGPIPE flakes, because `head` exiting early
# kills the writer.)
#
# The Python assertions matter as much as the compilers: tools/configure.py
# needs `tomllib` to read the config at all, Pillow to produce the Android
# launcher icons, and PyYAML for tools/workflow_check.sh's permission gate.
# Without them a job fails halfway through instead of the image failing here.
#
# actionlint, butler and the Android SDK/NDK are amd64-only by construction
# (see their install steps), so they are checked under TARGETARCH.
#
# THE TEST TOOLCHAIN (smoke/) is exercised the same way, and each piece has to
# DO its job, not print a banner: a profiled binary is built, run, merged and
# reported; cppcheck must refuse an out-of-bounds write and accept clean C++20;
# a sanitized binary must run clean AND be stopped by each sanitizer on the
# mistake it exists for; libFuzzer must finish 100 runs; Mull must report the
# one mutant smoke/mull.c leaves alive; mutmut must report the mutant only a
# Hypothesis property can kill. `expect` and `refuse` are `check` plus the text
# the output has to contain -- with exit 0 and non-zero respectively.
#
# All of it runs on both architectures: each is built on a runner of its own
# architecture (.github/workflows/docker-image.yaml), so nothing here is
# emulated. Under QEMU, which built arm64 until 2026-10, ASan's shadow memory
# did not map and the arm64 binaries were only linked.
COPY smoke/ /tmp/rmp-smoke/
RUN set -eu; \
    check() { \
        label="$1"; shift; \
        if ! out="$("$@" 2>&1)"; then \
            echo "SMOKE FAIL: ${label}: $* exited non-zero" >&2; \
            printf '%s\n' "$out" >&2; \
            return 1; \
        fi; \
        printf '  ok  %-14s %s\n' "$label" "$(printf '%s' "$out" | head -1)"; \
    }; \
    expect() { \
        label="$1"; want="$2"; shift 2; \
        if ! out="$("$@" 2>&1)"; then \
            echo "SMOKE FAIL: ${label}: $* exited non-zero" >&2; \
            printf '%s\n' "$out" >&2; \
            return 1; \
        fi; \
        case "$out" in \
            *"$want"*) printf '  ok  %-14s %s\n' "$label" "$want" ;; \
            *) echo "SMOKE FAIL: ${label}: $* printed no \"${want}\"" >&2; \
               printf '%s\n' "$out" >&2; \
               return 1 ;; \
        esac; \
    }; \
    refuse() { \
        label="$1"; want="$2"; shift 2; \
        if out="$("$@" 2>&1)"; then \
            echo "SMOKE FAIL: ${label}: $* exited 0; it had to be stopped with \"${want}\"" >&2; \
            printf '%s\n' "$out" >&2; \
            return 1; \
        fi; \
        case "$out" in \
            *"$want"*) printf '  ok  %-14s refused: %s\n' "$label" "$want" ;; \
            *) echo "SMOKE FAIL: ${label}: $* failed, but not with \"${want}\"" >&2; \
               printf '%s\n' "$out" >&2; \
               return 1 ;; \
        esac; \
    }; \
    check cmake        cmake --version; \
    check ninja        ninja --version; \
    check zig          zig version; \
    check gcc          gcc --version; \
    check clang        clang --version; \
    check gcc-aarch64  aarch64-linux-gnu-gcc --version; \
    check gcc-riscv64  riscv64-linux-gnu-gcc --version; \
    check emcc         emcc --version; \
    check java         java -version; \
    check objdump      objdump --version; \
    check upx          upx --version; \
    check pkg-config   pkg-config --version; \
    check clang-format clang-format --version; \
    check clang-tidy   clang-tidy --version; \
    check ccache       ccache --version; \
    check shellcheck   shellcheck --version; \
    check qemu-riscv64 qemu-riscv64-static -version; \
    # The DRM/KMS targets configure against exactly these four modules. A -dev
    # package that silently did not land is a cmake failure on a runner instead.
    check drm-headers  pkg-config --exists libdrm gbm egl glesv2; \
    # zip, exercised for real: `zip -v` prints a banner whether or not the tool
    # can actually write an archive, and the packaging steps need the writing
    # half. Round-trip through unzip, which those steps also use.
    printf 'smoke\n' > /tmp/smoke.txt; \
    check zip          zip -q -j /tmp/smoke.zip /tmp/smoke.txt; \
    check unzip        unzip -t /tmp/smoke.zip; \
    rm -f /tmp/smoke.txt /tmp/smoke.zip; \
    # xvfb-run STARTED, not merely present on PATH: it shells out to xauth and
    # to Xvfb, and either one being absent only shows up when it runs.
    check xvfb-run     xvfb-run -a -s "-screen 0 64x64x24" true; \
    check tomllib      python3 -c "import sys, tomllib; print('python', '.'.join(map(str, sys.version_info[:3])), '+ tomllib')"; \
    check pillow       python3 -c "import PIL; print('pillow', PIL.__version__)"; \
    check pyyaml       python3 -c "import yaml; print('pyyaml', yaml.__version__)"; \
    check llvm-cov     llvm-cov --version; \
    check llvm-profdata llvm-profdata --version; \
    check cppcheck     cppcheck --version; \
    check mull-runner  mull-runner-18 --version; \
    check py-test      python3 -c "import hypothesis, mutmut, pytest; print('hypothesis', hypothesis.__version__, '+ mutmut + pytest', pytest.__version__)"; \
    cd /tmp/rmp-smoke; \
    # Source-based coverage, end to end. The run must leave a .profraw, the
    # merge must read it, and the report must find coverage.c's mapping in it.
    check cov-build    clang -fprofile-instr-generate -fcoverage-mapping coverage.c -o coverage; \
    check cov-run      env LLVM_PROFILE_FILE=/tmp/rmp-smoke/coverage.profraw ./coverage; \
    check cov-merge    llvm-profdata merge -sparse coverage.profraw -o coverage.profdata; \
    expect cov-report  "coverage.c" llvm-cov report ./coverage -instr-profile=coverage.profdata; \
    # cppcheck analyses, it does not just parse: a known out-of-bounds write is
    # exit 1, and clean C++20 (designated initialisers, requires) is exit 0.
    refuse cppcheck-oob "arrayIndexOutOfBounds" \
        cppcheck -q --error-exitcode=1 --language=c++ --std=c++20 cppcheck_bad.cpp; \
    check cppcheck-ok  cppcheck -q --error-exitcode=1 --language=c++ --std=c++20 cppcheck_clean.cpp; \
    check san-build    clang++ -fsanitize=address,undefined -fno-sanitize-recover=all -g sanitize.cpp -o sanitize; \
    check fuzz-build   clang++ -fsanitize=fuzzer,address,undefined -g fuzz.cpp -o fuzz; \
    check mull-build   clang -fpass-plugin=/usr/lib/mull-ir-frontend-18 -g -grecord-command-line mull.c -o mull; \
    expect san-clean   "sum=4" ./sanitize; \
    refuse asan        "heap-buffer-overflow" ./sanitize heap; \
    refuse ubsan       "signed integer overflow" ./sanitize int; \
    refuse lsan        "detected memory leaks" ./sanitize leak; \
    expect libfuzzer   "Done 100 runs" ./fuzz -runs=100; \
    expect mull        "Mutation score: 75%" mull-runner-18 --allow-surviving ./mull; \
    # Hypothesis under pytest, and mutmut, which forks a pytest per mutant. No
    # bytecode: pytest's assertion rewriting would otherwise leave 2 MB of .pyc
    # in this layer.
    cd /tmp/rmp-smoke/python; \
    export PYTHONDONTWRITEBYTECODE=1; \
    expect pytest      "2 passed" python3 -m pytest -q -p no:cacheprovider tests; \
    expect mutmut-run  "1 files mutated" mutmut run; \
    expect mutmut      "x_at_least__mutmut_1: killed" mutmut results --all true; \
    cd /work; \
    rm -rf /tmp/rmp-smoke; \
    if [ "$TARGETARCH" = "amd64" ]; then \
        check actionlint  actionlint --version; \
        check butler      butler -V; \
        check android-ndk test -d "$ANDROID_NDK_HOME"; \
        check android-sdk test -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"; \
        expect gradle-home "warm_commit=${GRADLE_WARM_COMMIT}" cat "$GRADLE_USER_HOME/rmp-warm.properties"; \
    else \
        echo "  --  actionlint/butler/Android/Gradle home: amd64-only, absent on ${TARGETARCH} by design"; \
        if [ -e "$GRADLE_USER_HOME/rmp-warm.properties" ]; then \
            echo "SMOKE FAIL: ${TARGETARCH} carries a warmed Gradle home it cannot use" >&2; \
            exit 1; \
        fi; \
    fi; \
    echo "OK: image smoke check passed on ${TARGETARCH}"
