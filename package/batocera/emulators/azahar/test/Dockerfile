FROM debian:bookworm-slim

ENV HOME=/root
ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/main/main contrib non-free/' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git ca-certificates patch pkg-config ccache \
    clang lld llvm \
    libboost-dev libboost-serialization-dev libboost-iostreams-dev \
    libboost-regex-dev libboost-locale-dev libboost-math-dev libboost-container-dev \
    libfdk-aac-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libfmt-dev libopenal-dev libsdl2-dev \
    qt6-base-dev qt6-base-private-dev qt6-tools-dev qt6-tools-dev-tools qt6-multimedia-dev libqt6opengl6-dev \
    glslang-tools libgl1-mesa-dev libegl1-mesa-dev \
    && rm -rf /var/lib/apt/lists/*

ARG AZAHAR_VERSION=2125.1.2
RUN git clone https://github.com/azahar-emu/azahar.git /src/azahar \
    && git -C /src/azahar checkout ${AZAHAR_VERSION} \
    && git -C /src/azahar submodule update --init --recursive

# Apply Batocera patches needed for dual-window support, clean exit, and Clang C++20 structured binding compatibility.
# Note: 001-fix-qt6.10.patch is only for Buildroot's newer Qt 6.10 toolchain and
# breaks on Debian Bookworm (Qt 6.4), where GuiPrivate is internal to Qt6::Gui.
COPY 002-no-translate-windows-titles.patch 003-fix-window-close.patch 004-fix-vulkan-structured-binding-capture.patch 005-fix-egl-null-context-crash.patch 006-fix-panvk-cmdbuf-leak.patch 007-disable-panvk-timeline-semaphores.patch /tmp/patches/
RUN for p in /tmp/patches/*.patch; do \
        if [ -f "$p" ]; then \
            echo "Applying $p"; \
            patch -d /src/azahar -p1 < "$p" || exit 1; \
        fi \
    done

ENV CCACHE_DIR=/root/.cache/ccache

RUN --mount=type=cache,target=/root/.cache/ccache \
    cmake -S /src/azahar -B /build/azahar -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_TESTS=OFF \
        -DENABLE_ROOM=OFF \
        -DCITRA_WARNINGS_AS_ERRORS=OFF \
        -DENABLE_WEB_SERVICE=OFF \
        -DUSE_DISCORD_PRESENCE=OFF \
        -DENABLE_SOFTWARE_RENDERER=ON \
        -DENABLE_OPENAL=ON \
        -DUSE_SYSTEM_OPENAL=OFF \
        -DUSE_SYSTEM_BOOST=OFF \
        -DENABLE_SDL2=ON \
        -DUSE_SYSTEM_SDL2=ON \
        -DENABLE_QT=ON \
        -DENABLE_QT_TRANSLATION=OFF \
        -DENABLE_QT_UPDATE_CHECKER=OFF \
        -DENABLE_LTO=OFF \
        -DENABLE_OPENGL=ON \
        -DENABLE_VULKAN=ON \
    && ninja -C /build/azahar \
    && cmake --install /build/azahar --prefix /usr/local

ENTRYPOINT ["/usr/local/bin/azahar"]
