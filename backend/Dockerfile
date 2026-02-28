# Build stage
FROM swift:5.9-jammy AS build

WORKDIR /build

# Copy package files first for dependency caching
COPY Package.swift Package.resolved* ./
RUN swift package resolve

# Copy source code
COPY Sources/ Sources/

# Build in release mode
RUN swift build -c release --static-swift-stdlib

# Run stage
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    libcurl4 \
    libxml2 \
    libssl3 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /build/.build/release/App /app/App

EXPOSE 8080

CMD ["/bin/sh", "-c", "./App serve --env production --hostname 0.0.0.0 --port ${PORT:-8080}"]
