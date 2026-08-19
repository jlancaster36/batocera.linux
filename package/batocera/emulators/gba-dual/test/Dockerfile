# Local/CI test environment for gba-dual: builds the exact pinned mGBA commit
# (see LIBRETRO_MGBA_VERSION in ../../retroarch/libretro/libretro-mgba/libretro-mgba.mk)
# as a native library, then builds and smoke-tests gba-dual against it.
# This does NOT replace the Buildroot package; it exists for fast local iteration
# since the full Batocera Buildroot toolchain is too slow for edit/compile loops.
FROM debian:bookworm-slim

# mCoreLoadConfig() reads $HOME/.config unconditionally; a bare `docker run`
# with an exec-form entrypoint has no HOME set, which segfaults mGBA's config
# loader (unchecked getenv("HOME") -> snprintf("%s/.config", NULL)).
ENV HOME=/root

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build pkg-config git ca-certificates \
    libsdl2-dev libpng-dev libzip-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Keep in sync with LIBRETRO_MGBA_VERSION in libretro-mgba.mk.
ARG MGBA_VERSION=97c4de34889fc990119f7d9a95167f623f17e27d

RUN git clone https://github.com/mgba-emu/mgba.git /src/mgba \
    && git -C /src/mgba checkout ${MGBA_VERSION}

RUN cmake -S /src/mgba -B /build/mgba -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_LIBRETRO=OFF -DBUILD_QT=OFF -DBUILD_SDL=OFF -DSKIP_LIBRARY=OFF \
        -DUSE_DISCORD_RPC=OFF -DUSE_SQLITE3=OFF -DUSE_EDITLINE=OFF -DUSE_EPOXY=OFF \
        -DUSE_LIBZIP=OFF -DUSE_MINIZIP=OFF -DUSE_FFMPEG=OFF \
    && cmake --build /build/mgba --target mgba \
    && cmake --install /build/mgba --prefix /usr/local

COPY . /src/gba-dual
RUN cmake -S /src/gba-dual -B /build/gba-dual -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DMGBA_INCLUDE_DIR=/usr/local/include \
    && cmake --build /build/gba-dual

ENTRYPOINT ["/build/gba-dual/gba-dual"]
