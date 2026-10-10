# raylib-build-image

Frozen CI build image for [`raylib_multiplatform`](https://github.com/omardev29/raylib_multiplatform).
The template's Linux jobs run **inside this image** (`container:`), so every
compiler and library is pinned and nothing is downloaded at job time — that's
what makes builds stable and reproducible.

## What "frozen" means here

Four separate things, all of which have to hold or the word is marketing:

| Layer | How it's pinned |
|---|---|
| Base image | `ubuntu:24.04@sha256:…` — by **digest**, not by tag |
| apt packages | Every source points at `snapshot.ubuntu.com/ubuntu/<TIMESTAMP>`, so `apt-get install` resolves to the same bytes forever |
| Downloads (CMake, Ninja, zig, UPX, butler, actionlint, Mull, Android cmdline-tools) | Hard-coded `sha256sum -c` on every artifact |
| Python test tools | `python/requirements-ci.txt`: every package pinned with `==` and every wheel by sha256, installed with `--require-hashes --only-binary=:all:` |
| Emscripten | emsdk fetched by **commit SHA**, not by tag (tags are movable) |
| Gradle home | Warmed from the framework at a pinned **commit SHA**, and proven `--offline` before the image is published |

Everything lives in the `ARG` block at the top of the `Dockerfile`. Bump a
version deliberately, never by accident — and when you do, bump the matching row
in the template's `thirdparty/FROZEN_VERSIONS.md`; the template's
`tools/versions_check.sh` fails CI if the two drift apart.

The image also writes `/etc/raylib-build-image.json`, a manifest of every pinned
version plus the architecture. Every containerised CI job `cat`s it as its first
step, so a failing log always states exactly which toolchain produced it.

**What "frozen" does not mean here.** Rebuilding this `Dockerfile` unchanged
gives you the same *contents* — same packages, same tarballs, same compilers —
but not necessarily the same image digest. Docker records creation timestamps in
the image config, so two builds minutes apart differ at the metadata level even
when every byte of every layer matches. Bit-identical rebuilds would need
`SOURCE_DATE_EPOCH` plus buildx's `rewrite-timestamp`, which is deliberately not
enabled: the property that matters for CI is that the toolchain cannot change
underneath you, and that is what the pins above buy. Consumers pin the digest
anyway, so they are unaffected either way.

## Contents

Multiarch (`linux/amd64` + `linux/arm64`). Includes:

- C/C++ compilers (gcc, g++, clang), pinned **CMake** and **Ninja**, ccache
- raylib desktop deps (X11 / Wayland / Mesa) + `xvfb` for headless render tests
- Cross toolchains: `aarch64-linux-gnu`, `riscv64-linux-gnu` (+ riscv64 X11 via
  multiarch) and `qemu-user-static` to run foreign binaries
- **Emscripten** (Web), pinned
- **Android** SDK/NDK + JDK 17 (amd64 only — the NDK host is x86_64)
- Python 3.12 with `tomllib` (stdlib), **Pillow** and **PyYAML** — the three
  things `tools/configure.py`, the Android icon generation and
  `tools/workflow_check.sh` fail without
- The test toolchain:
  - the rest of **LLVM 18** at the system clang's own version (18.1.3):
    `llvm-cov`, `llvm-profdata`, `llvm-cxxfilt`, `llvm-symbolizer`, and
    **compiler-rt** (`libclang-rt-18-dev`), without which that clang compiles
    `-fsanitize=address`, `-fsanitize=fuzzer` and `-fprofile-instr-generate`
    and then cannot link them
  - **cppcheck** (2.13.0, the snapshot's)
  - **Mull** 0.34.1 for LLVM 18.1.3 — `mull-runner-18` and the clang plugin
    `/usr/lib/mull-ir-frontend-18`; the build refuses a Mull made for another
    LLVM
  - **Hypothesis**, **mutmut** and **pytest**, from a hashed lock (below)
- A **Gradle home** at `/opt/gradle-home` (`GRADLE_USER_HOME`) that builds the
  Android project `--offline` (amd64 only; below)
- `actionlint` **and `shellcheck`** — the second is not optional. actionlint has
  no shell analysis of its own: everything it says about a `run:` block comes
  from shelling out to `shellcheck`, and with the binary absent it disables the
  rule and exits 0 on the same file. Verified both ways against a fixture
  workflow (SC2086 reported with it, `Found total 0 errors` without it). The
  hosted runners ship shellcheck, so this only went quiet when the lint job
  moved into the image.
- A smoke check that **invokes** every tool a CI job invokes — not just the
  compilers but `xvfb-run`, `upx`, `objdump`, `zip`, `pkg-config` (including
  the DRM/GBM/EGL modules), `clang-format`, `clang-tidy`, `actionlint` and
  `butler`. A tool that is installed but never run is a tool you find out about
  twenty minutes into a matrix, on a change that had nothing to do with it.
  The test toolchain is held to more than running: from `smoke/`, a profiled
  binary is built, run, merged and reported; cppcheck must refuse an
  out-of-bounds write and accept clean C++20; a sanitized binary must run clean
  **and** be stopped by ASan, UBSan and LSan on the mistake each exists for;
  libFuzzer must finish 100 runs; Mull must report the one mutant `smoke/mull.c`
  leaves alive; and mutmut must report killed the one mutant only a Hypothesis
  property can kill.

### Architecture differences

`arm64` has **no Android SDK and no riscv64 multiarch** — both are gated on
`TARGETARCH=amd64` because the NDK host binaries are x86_64-only. The manifest
records the architecture so this is never a surprise at 2 a.m.

It follows that `arm64` has **no warmed Gradle home** either:
`/opt/gradle-home` exists there, empty and writable, so `GRADLE_USER_HOME`
never points at nothing, and the manifest has no `gradle`, `agp`,
`play_services_ads` or `gradle_warm_commit` keys (absent, not faked).
actionlint and butler are amd64-only too.

The test toolchain is installed on **both**, and the smoke check runs all of it
on both -- the sanitizers stopping their own mistakes, libFuzzer, Mull, pytest
with Hypothesis and mutmut -- because each architecture is built on a runner of
its own architecture, with nothing emulated. (Until 2026-10 arm64 was built
under QEMU, where ASan's shadow memory does not map, and those binaries were
only linked there.)

## Why there is a Gradle home in the image

Every Android job used to download Gradle and every Maven dependency, about six
and a half minutes of it per run. The framework's `_android.yml` cached
`~/.gradle`, but inside a container job that is `/github/home` while Java's
`user.home` is `/root`, so the cache never held anything and was never saved.
A download at job time is exactly what this image exists to remove.

So `GRADLE_USER_HOME=/opt/gradle-home`, the same path for every user (the job's
root, and the framework's `dev_shell.sh`, which runs as `--user $(id -u)` —
hence world-writable), warmed at image build time:

1. The framework is fetched at `GRADLE_WARM_COMMIT` and built the way
   `_android.yml` builds it — `configure.py --require-icons`, a throwaway
   keystore, `assembleDebug` and `bundleRelease` as separate `--no-daemon`
   builds — with AdMob **on**, and again with it **off** (without
   play-services-ads, dependency resolution can settle on other androidx
   versions).
2. The wrapper's zip (138 MB) and the daemon logs are deleted; the unpacked
   distribution is what runs.
3. Both variants are built **again with `--offline`** from a clean tree. If
   anything is missing, the image build fails there, not the first Android job
   after the bump.
4. `init.d/rmp-keep-cache.gradle` disables Gradle's cache cleanup. Without it,
   a `--no-daemon` build deletes whatever it has not touched for 30 days, so a
   month after publishing an `assembleDebug` deletes the release-only
   artifacts and the `bundleRelease --offline` after it fails. Seen with the
   clock faked 60 days ahead: with the default cleanup, `bundleRelease
   --offline` died on lint's jars ("No cached version available for offline
   mode"); with this file, both builds pass.
5. `rmp-warm.properties` records `gradle`, `agp`, `play_services_ads` and
   `warm_commit` (read from the clone with the regexes the framework's
   `versions_check.sh` uses), and the manifest copies them.

A game that adds a Gradle dependency of its own is not in this home and fails
`--offline` loudly. Bump `GRADLE_WARM_COMMIT` whenever raymob's Gradle, AGP or
dependencies change.

## The Python lock

`python/requirements-ci.in` holds the top-level pins; `python/requirements-ci.txt`
is generated from it by `python/lock.py` and is what the Dockerfile installs.
The lock pins the whole graph with `==` and carries the sha256 of every wheel
pip may pick for CPython 3.12 on manylinux x86_64 **and** aarch64 — downloaded
and hashed by `lock.py` and checked against PyPI's published digest, not copied
from an index. PyYAML and Pygments are pinned to the versions **apt** installs:
both are Debian packages in this image (Pygments arrives as a Depends of
cppcheck), and pip cannot uninstall a Debian package, so any other version
fails the build with `Cannot uninstall Pygments 2.17.2, RECORD file not found`.
That pin is why textual (mutmut's UI) resolves to 4.0.0: newer textual needs a
newer Pygments.

To regenerate it, inside this image, from the repository root (the command is
also in `lock.py`'s docstring):

```sh
docker run --rm -v "$PWD":/w -w /w ghcr.io/omardev29/raylib-build:latest sh -c '
    apt-get update -qq && apt-get install -y -qq python3-venv >/dev/null &&
    python3 -m venv /tmp/v && /tmp/v/bin/pip install -q pip-tools==7.6.2 &&
    /tmp/v/bin/python python/lock.py'
```

## Publish

`.github/workflows/docker-image.yaml`:

- **Each architecture builds on a runner of its own architecture**:
  `ubuntu-24.04` for amd64, `ubuntu-24.04-arm` for arm64 (free for a public
  repository). Nothing is emulated, and each job runs `verify/image.sh` inside
  the image it built, natively, checking the image's own `arch` against the
  one it was built for. arm64 used to build under QEMU on the amd64 runner, and
  a build with nothing cached took an hour.
- **Pull requests** build and verify both architectures **without pushing**,
  so a broken `Dockerfile` is caught before it reaches `main`.
- **Manual runs** (`gh workflow run docker-image.yaml --ref <branch>`) publish
  only on `main`. On any other branch they build and verify both
  architectures like a pull request and push nothing — not `:latest`, which
  the framework's canary runs on, and not a build cache.
- **Push to `main`** (when `Dockerfile`, `python/`, `smoke/`, `verify/` or the
  workflow change): each build job pushes its image **by digest**, untagged,
  and verifies that exact digest by running it. A `publish` job then makes the
  multi-architecture list of the two, tagged with the commit SHA; checks that
  the list holds exactly the two verified digests, each on its platform; only
  then moves `latest` to it; and prints the list's **immutable digest** to the
  run summary. Verifying only amd64 once left the arm64 image (what the `arm64`
  and `drm-arm64` jobs run inside) published without ever having been executed.

## Setup

1. Create this repository on GitHub (e.g. `raylib-build-image`).
2. `git init`, add these files, commit and push.
3. The workflow publishes the image (needs the default `GITHUB_TOKEN`; the repo
   must allow Packages writes — on by default for public repos).
4. Copy the digest from the run summary and pin it in the framework, in the
   **three** places that carry it — `tools/versions_check.sh` fails if any two
   of them disagree:

   | File | What holds it |
   |---|---|
   | `.github/workflows/ci.yml` | `PINNED_IMAGE:` in the `config` job |
   | `.github/workflows/web-backends.yml` | the job's `container: image:` |
   | `thirdparty/FROZEN_VERSIONS.md` | the `build_image_digest` row of its `versions` block |

   **Pin the digest, not `:latest`.** A tag can be moved out from under you; a
   digest cannot.

## Notes

- **rrespacker is NOT in the image.** It is paid/closed. The template uses the
  open `tools/rres_pack` instead (built by CMake, used by `pack_resources`).
- The image is large (Android + emsdk + cross toolchains). Layer caching goes to
  a **registry** cache (`:buildcache`), not the Actions cache — at ~10 GB the
  image blows straight through the 10 GB per-repo Actions cache limit and would
  evict itself on every run.
- Actions in the workflow are pinned by full SHA and use Node 22+ (Node 20
  actions are being deprecated by GitHub). Dependabot watches the actions; the
  base image digest is bumped by hand (`.github/dependabot.yml` says why).
