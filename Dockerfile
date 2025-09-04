# syntax=docker/dockerfile:1.6

############################
# Builder
############################
FROM debian:bookworm-slim AS builder
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    binutils \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    libssl-dev \
    zlib1g-dev \
    pkg-config \
    tcl \
    patch \
    file \
 && rm -rf /var/lib/apt/lists/*

# belabox patched srt
ARG BELABOX_SRT_VERSION=master
RUN git clone https://github.com/BELABOX/srt.git /build/srt \
 && cd /build/srt \
 && git checkout "$BELABOX_SRT_VERSION" \
 && ./configure --prefix=/usr/local \
 && make -j"$(nproc)" \
 && make install \
 && ldconfig

# belabox srtla
ARG SRTLA_VERSION=main
RUN git clone https://github.com/BELABOX/srtla.git /build/srtla \
 && cd /build/srtla \
 && git checkout "$SRTLA_VERSION" \
 && make -j"$(nproc)" \
 && install -m 0755 /build/srtla/srtla_rec /build/srtla/srtla_send /usr/local/bin

# srt-live-server (+Patches)
COPY patches/sls-SRTLA.patch \
     patches/sls-version.patch \
     patches/480f73dd17320666944d3864863382ba63694046.patch /tmp/

ARG SRT_LIVE_SERVER_VERSION=master
RUN git clone https://github.com/IRLDeck/srt-live-server.git /build/srt-live-server \
 && cd /build/srt-live-server \
 && git checkout "$SRT_LIVE_SERVER_VERSION" \
 && patch -p1 < /tmp/sls-SRTLA.patch \
 && patch -p1 < /tmp/sls-version.patch || true \
 && patch -p1 < /tmp/480f73dd17320666944d3864863382ba63694046.patch \
 # fehlenden Header für time/localtime/strftime ergänzen
 && grep -q '#include <time.h>' slscore/common.cpp || sed -i '1i #include <time.h>' slscore/common.cpp \
 && LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}" make -j"$(nproc)" \
 && cp bin/* /usr/local/bin

# NOALBS 2 (Rust, Edition 2024 -> Nightly)
ARG NOALBS_VERSION=v2
ENV CARGO_HOME=/root/.cargo \
    RUSTUP_HOME=/root/.rustup \
    RUSTUP_TOOLCHAIN=nightly
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal \
 && rustup toolchain install nightly \
 && rustup default nightly \
 && rustc --version && cargo --version
RUN git clone https://github.com/715209/nginx-obs-automatic-low-bitrate-switching /app \
 && cd /app \
 && git checkout "$NOALBS_VERSION" \
 && cargo build --release \
 && strip target/release/noalbs

############################
# Runtime
############################
FROM debian:bookworm-slim
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    lsof \
    procps \
    supervisor \
    libssl3 \
    zlib1g \
    libstdc++6 \
    tzdata \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/include /usr/local/include
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /app/target/release/noalbs /usr/local/bin/noalbs

COPY files/sls.conf /etc/sls/sls.conf
COPY files/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY files/logprefix /usr/local/bin/logprefix
COPY config/config.json.example /app/config.json
COPY config/env.example /app/.env

RUN ldconfig && chmod 755 /usr/local/bin/logprefix

EXPOSE 5000/udp 8181/tcp 8282/udp
CMD ["/usr/bin/supervisord"]
