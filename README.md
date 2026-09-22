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
| Downloads (CMake, Ninja, Android cmdline-tools) | Hard-coded `sha256sum -c` on every artifact |
| Emscripten | emsdk fetched by **commit SHA**, not by tag (tags are movable) |

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

### Architecture differences

`arm64` has **no Android SDK and no riscv64 multiarch** — both are gated on
`TARGETARCH=amd64` because the NDK host binaries are x86_64-only. The manifest
records the architecture so this is never a surprise at 2 a.m.

## Publish

`.github/workflows/docker-image.yaml`:

- **Pull requests** build both architectures **without pushing**, so a broken
  `Dockerfile` is caught before it reaches `main`.
- **Push to `main`** (when `Dockerfile` changes) builds and pushes to
  `ghcr.io/<owner>/raylib-build`, tags `latest` and the commit SHA, then prints
  the **immutable digest** to the run summary and verifies the published image
  by actually running it — on **both** `linux/amd64` and `linux/arm64`, and
  checking each one's manifest `arch` against the platform that was asked for.
  Verifying only amd64 left the arm64 manifest (what the `arm64` and `drm-arm64`
  jobs run inside) published without ever having been executed.

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
  actions are being deprecated by GitHub). Dependabot watches both the actions
  and the base image.
