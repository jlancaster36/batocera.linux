# Baseline test environment: builds the exact pinned mGBA commit (see
# LIBRETRO_MGBA_VERSION in ../../retroarch/libretro/libretro-mgba/libretro-mgba.mk)
# completely unmodified, with no gba-dual code involved, and runs mGBA's own
# cmocka unit test suite (CPU/PPU/memory correctness). This has nothing to do
# with our changes: it exists so that if something breaks later, we can tell
# whether the pinned upstream commit itself is unhealthy before blaming gba-dual.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build pkg-config git ca-certificates \
    libpng-dev libzip-dev zlib1g-dev libcmocka-dev \
    && rm -rf /var/lib/apt/lists/*

# Keep in sync with LIBRETRO_MGBA_VERSION in libretro-mgba.mk.
ARG MGBA_VERSION=97c4de34889fc990119f7d9a95167f623f17e27d

RUN git clone https://github.com/mgba-emu/mgba.git /src/mgba \
    && git -C /src/mgba checkout ${MGBA_VERSION}

RUN cmake -S /src/mgba -B /build/mgba -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_LIBRETRO=OFF -DBUILD_QT=OFF -DBUILD_SDL=OFF -DSKIP_LIBRARY=OFF \
        -DBUILD_SUITE=ON -DBUILD_TEST=ON \
        -DUSE_DISCORD_RPC=OFF -DUSE_SQLITE3=OFF -DUSE_EDITLINE=OFF -DUSE_EPOXY=OFF \
        -DUSE_LIBZIP=OFF -DUSE_MINIZIP=OFF -DUSE_FFMPEG=OFF \
    && cmake --build /build/mgba \
    && ctest --test-dir /build/mgba --output-on-failure

ENTRYPOINT ["ctest", "--test-dir", "/build/mgba", "--output-on-failure"]
