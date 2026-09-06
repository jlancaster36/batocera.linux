# Fast native smoke-test build for the MelonDS Batocera package.
# This mirrors the gba-dual workflow: build the upstream project in a Docker
# container, install it locally, and smoke-test it without a ROM or display.
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

# Apply Batocera's own patch stack so this matches the production build,
# not vanilla upstream (patches live one directory up, alongside this Dockerfile).
COPY *.patch /tmp/patches/
RUN for p in /tmp/patches/*.patch; do \
        echo "Applying $p"; \
        patch -d /src/melonDS -p1 < "$p"; \
    done

RUN cmake -S /src/melonDS -B /build/melonDS -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=OFF \
        -DUSE_QT6=ON \
        -DENABLE_WAYLAND=OFF \
    && cmake --build /build/melonDS \
    && cmake --install /build/melonDS --prefix /usr/local

ENTRYPOINT ["/usr/local/bin/melonDS"]
