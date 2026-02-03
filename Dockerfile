# Multi-stage Dockerfile for cnbhl/basicstation-rpi64
# Builds and runs Basic Station with SX1302/SX1303 corecell support
#
# Build:  docker build -t basicstation .
# Run:    docker run -d --privileged --network host \
#           -e BOARD=PG1302 -e REGION=eu1 -e GATEWAY_EUI=auto \
#           -e CUPS_KEY="NNSXS.xxx..." basicstation

ARG VARIANT=std

# =============================================================================
# Stage 1: Builder
# =============================================================================
FROM debian:bookworm-slim AS builder

ARG VARIANT=std

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        curl \
        ca-certificates \
        python3 \
        python3-jsonschema \
        python3-jinja2 \
    && rm -rf /var/lib/apt/lists/*

COPY . /build
WORKDIR /build

# Build station binary (deps/*/prep.sh clone HAL and mbedtls via git)
RUN make platform=corecell variant=${VARIANT}

# Build chip_id tool for EUI auto-detection
RUN gcc -std=gnu11 -O2 \
        -I build-corecell-${VARIANT}/include/lgw \
        tools/chip_id/chip_id.c tools/chip_id/log_stub.c \
        -L build-corecell-${VARIANT}/lib -llgw1302 -lm -lpthread -lrt \
        -o build-corecell-${VARIANT}/bin/chip_id

# =============================================================================
# Stage 2: Runner
# =============================================================================
FROM debian:bookworm-slim

ARG VARIANT=std

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create directory structure
RUN mkdir -p /app/bin /app/scripts /app/templates /app/config

# Copy binaries from builder
COPY --from=builder /build/build-corecell-${VARIANT}/bin/station /app/bin/station
COPY --from=builder /build/build-corecell-${VARIANT}/bin/chip_id /app/bin/chip_id

# Copy runtime scripts
COPY examples/corecell/cups-ttn/reset_lgw.sh /app/scripts/reset_lgw.sh
COPY examples/corecell/cups-ttn/rinit.sh /app/scripts/rinit.sh

# Copy templates
COPY examples/corecell/cups-ttn/station.conf.template /app/templates/station.conf.template
COPY examples/corecell/cups-ttn/board.conf.template /app/templates/board.conf.template

# Copy entrypoint
COPY docker/entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/bin/station /app/bin/chip_id \
              /app/scripts/reset_lgw.sh /app/scripts/rinit.sh \
              /app/entrypoint.sh

WORKDIR /app/config

ENTRYPOINT ["/app/entrypoint.sh"]
