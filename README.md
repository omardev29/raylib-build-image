# raylib-build-image

Frozen CI build image for the `raylib_cmake_template`. The template's Linux CI
jobs run **inside this image** (`container:`), so every compiler/library is
pinned and nothing is downloaded at job time — that's what makes builds stable
and reproducible.

## Contents

Multiarch (`linux/amd64` + `linux/arm64`). Includes:

- C/C++ compilers (gcc, g++, clang), pinned **CMake** and **Ninja**, ccache
- raylib desktop deps (X11 / Wayland / Mesa)
- Cross toolchains: `aarch64-linux-gnu`, `riscv64-linux-gnu` (+ riscv64 X11 via
  multiarch) and `qemu-user-static` to run foreign binaries
- **Emscripten** (Web), pinned
- **Android** SDK/NDK + JDK 17 (amd64 only — the NDK host is x86_64)
- A smoke check that fails the image build if a tool is broken

All versions are pinned in the `ENV` block at the top of the `Dockerfile`.

## Publish

`.github/workflows/docker-image.yaml` builds and pushes the image to GHCR:
`ghcr.io/<owner>/raylib-build` (tags: `latest` and the commit SHA). It runs when
`Dockerfile` changes on `main`, or manually via *workflow_dispatch*.

## Setup

1. Create this repository on GitHub (e.g. `raylib-build-image`).
2. `git init`, add these files, commit and push.
3. The workflow publishes the image (needs the default `GITHUB_TOKEN`; the repo
   must allow Packages writes — on by default for public repos).
4. In `raylib_cmake_template/.github/workflows/build.yaml`, set `BUILD_IMAGE` to
   `ghcr.io/<your-owner>/raylib-build:latest` (or pin the SHA tag / `@sha256:…`
   digest for full reproducibility).

## Notes

- **rrespacker is NOT in the image.** It is paid/closed. The template uses the
  open `tools/rres_pack` instead (built by CMake, used by `pack_resources`).
- The image is large (Android + emsdk + cross toolchains). If pull time becomes
  a problem, split it into per-purpose images later.
- Actions in the workflow are pinned by full SHA and use Node 22+ (Node 20
  actions are being deprecated by GitHub).
