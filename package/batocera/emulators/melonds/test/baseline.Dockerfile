# Baseline upstream build for melonDS at the pinned tag used by Batocera.
# This is the regression guard: if it fails, the problem is upstream or the pin,
# not the Batocera generator or local feature work.
FROM debian:bookworm-slim

ENV HOME=/root

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build pkg-config git ca-certificates \
    libsdl2-dev libpng-dev libarchive-dev libenet-dev libslirp-dev \
    libepoxy-dev libgl1-mesa-dev libssl-dev qt6-base-dev qt6-base-private-dev \
    qt6-svg-dev qt6-multimedia-dev libqt6opengl6-dev libzstd-dev libfaad-dev \
    && rm -rf /var/lib/apt/lists/*

ARG MELONDS_VERSION=1.1

RUN git clone https://github.com/Arisotura/melonDS.git /src/melonDS \
    && git -C /src/melonDS checkout ${MELONDS_VERSION}

RUN cmake -S /src/melonDS -B /build/melonDS -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=OFF \
        -DUSE_QT6=ON \
        -DENABLE_WAYLAND=OFF \
    && cmake --build /build/melonDS \
    && cmake --install /build/melonDS --prefix /usr/local

CMD ["/usr/local/bin/melonDS", "--help"]
