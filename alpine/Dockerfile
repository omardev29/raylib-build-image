# raylib_multiplatform -- the Alpine its musl binary is started on
#
#   ghcr.io/omardev29/raylib-run-alpine
#
# The framework's `musl-x64-run` job starts the linux-x64-musl game on Alpine,
# twice: the headless build, which renders the golden frame in software, and
# the archive a player downloads, which is a desktop program and needs what an
# Alpine desktop has -- an X server, Mesa, and the X libraries GLFW opens with
# dlopen(). That job used to pull `alpine@sha256:...` from Docker Hub and
# `apk add` the desktop half at job time, and a Linux job downloads nothing:
# this image is that Alpine, with that desktop already in it, pinned by digest
# in the framework like the build image is.
#
# It is NOT the job's container. The runner injects a glibc-linked Node into a
# container job to run actions/checkout and friends, and in a musl-only image it
# does not start; the job runs on the ordinary runner and enters this image with
# `docker run` for the commands that matter.
#
# AMD64 ONLY. The job is x64 (linux-x64-musl is the one musl target), so this
# image is built for linux/amd64 and refuses to build for anything else.
#
# WHAT IS PINNED, AND WHAT IS NOT. The base is pinned by digest. The packages
# are not pinned to versions: Alpine keeps one version of each package per
# release branch and deletes the one it replaces, so an `apk add foo=1.2-r0`
# builds today and fails the day a security fix lands, and there is no
# snapshot archive to point at, the way the build image points at
# snapshot.ubuntu.com. What CI runs is frozen by the image digest the framework
# pins; what a rebuild would install floats within v3.20, and the manifest
# (/etc/raylib-run-alpine.json) records every installed package and version,
# read out of apk's own database, so two builds can be compared line by line.
#
# NO INIT IS BAKED IN. The job starts the shipped game under xvfb-run with
# `docker run --init`, because xvfb-run as a container's PID 1 hangs (it waits
# for Xvfb's SIGUSR1 and the game never starts; busybox's `timeout` cannot end
# it either). That init is the engine's own -- docker-init, which is tini, ships
# with Docker on the runner, and podman brings catatonit -- so nothing is
# downloaded for it, and baking tini in as well would put two inits in the
# job's container for no gain. The hang belongs to how a container is started,
# and the job is where that is decided and tested.
#
#   docker build -t raylib-run-alpine alpine/

# Alpine 3.20.10, by digest: the one the framework's job pulled from Docker Hub
# until this image replaced it. ARG-before-FROM is the only way to parameterise
# the base image.
ARG ALPINE_DIGEST=sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e

# ---------------------------------------------------------------------------
# The smoke program, built against this same Alpine so it links the same musl
# and the same Mesa. Only its binary reaches the image; the compiler does not.
# ---------------------------------------------------------------------------
FROM alpine:3.20.10@${ALPINE_DIGEST} AS smoke
RUN apk add --no-cache -q gcc musl-dev libx11-dev mesa-dev
COPY smoke/glx.c /src/glx.c
RUN gcc -std=c99 -O2 -Wall -Wextra -Werror /src/glx.c -o /rmp-glx-smoke -lGL -lX11 \
    && strip /rmp-glx-smoke

# ---------------------------------------------------------------------------
# The image.
# ---------------------------------------------------------------------------
FROM alpine:3.20.10@${ALPINE_DIGEST}
ARG ALPINE_DIGEST

# Exactly what the job used to install at job time, and nothing else:
#   xvfb-run          Xvfb, xauth and the wrapper that starts the game on it
#   mesa-gl           libGL.so.1, which GLFW opens for a GLX context
#   mesa-dri-gallium  the drivers, llvmpipe among them (it pulls in llvm17-libs)
#   libxcursor libxrandr libxi libxinerama
#                     what GLFW's X11 backend dlopen()s beside libX11
ARG PACKAGES="xvfb-run mesa-gl mesa-dri-gallium libxcursor libxrandr libxi libxinerama"

RUN set -eu; \
    arch="$(apk --print-arch)"; \
    if [ "$arch" != x86_64 ]; then \
        echo "FAIL: this image is amd64 only (musl-x64-run is the one job that runs it), and this build is ${arch}" >&2; \
        exit 1; \
    fi; \
    # Unquoted: one word per package.
    apk add --no-cache -q $PACKAGES

COPY --from=smoke /rmp-glx-smoke /usr/local/bin/rmp-glx-smoke

# ---------------------------------------------------------------------------
# Manifest. The framework's job prints it first, so a log always says which
# Alpine and which Mesa it ran on. Every installed package with its version,
# read from apk's database rather than from this file, so it says what IS in
# the image; every package asked for above must be among them with a version.
# ---------------------------------------------------------------------------
RUN set -eu; \
    db=/lib/apk/db/installed; \
    for p in $PACKAGES; do \
        v="$(awk -v p="$p" '$0 == "P:" p { found = 1; next } found && /^V:/ { print substr($0, 3); exit }' "$db")"; \
        if [ -z "$v" ]; then echo "FAIL: $p was asked for and is not installed" >&2; exit 1; fi; \
    done; \
    case "$(apk --print-arch)" in x86_64) arch=amd64 ;; *) arch="$(apk --print-arch)" ;; esac; \
    { \
      echo '{'; \
      printf '  "image": "%s",\n' raylib-run-alpine; \
      printf '  "arch": "%s",\n' "$arch"; \
      printf '  "alpine": "%s",\n' "$(cat /etc/alpine-release)"; \
      printf '  "alpine_digest": "%s",\n' "${ALPINE_DIGEST}"; \
      printf '  "requested": "%s",\n' "$PACKAGES"; \
      echo '  "packages": {'; \
      awk '/^P:/ { p = substr($0, 3) } /^V:/ { printf "    \"%s\": \"%s\",\n", p, substr($0, 3) }' "$db" \
        | sort | sed '$ s/,$//'; \
      echo '  }'; \
      echo '}'; \
    } > /etc/raylib-run-alpine.json; \
    cat /etc/raylib-run-alpine.json; \
    if grep -n '": ""' /etc/raylib-run-alpine.json; then \
        echo "FAIL: a manifest key above read an empty value" >&2; \
        exit 1; \
    fi

# ---------------------------------------------------------------------------
# Smoke check: the job, in miniature. A program started under xvfb-run gets a
# GLX context on llvmpipe, draws a triangle and reads back the pixels it drew
# (smoke/glx.c). Packages that are installed and cannot draw fail here, at
# build time, and not twenty minutes into the framework's matrix.
#
# The shell is this RUN's PID 1 and xvfb-run its child -- never `exec`ed, so
# the PID 1 hang described at the top cannot happen here either.
#
# Mesa 24 tries zink before anything else and says so -- "ZINK: failed to load
# libvulkan.so.1", then "glx: failed to create drisw screen" -- and only then
# settles on llvmpipe. Those two lines are expected, here and in the
# framework's log; the renderer and the pixels are what decide.
# ---------------------------------------------------------------------------
RUN set -eu; \
    timeout 120 xvfb-run -a -s "-screen 0 64x64x24" rmp-glx-smoke > /tmp/smoke.log 2>&1 \
        || { cat /tmp/smoke.log; echo "FAIL: the GLX smoke check failed" >&2; exit 1; }; \
    cat /tmp/smoke.log; \
    grep -q '^RMP_GLX_SMOKE_OK .*llvmpipe' /tmp/smoke.log; \
    rm -f /tmp/smoke.log; \
    echo "OK: Xvfb, GLX and llvmpipe draw"
