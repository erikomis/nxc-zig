#!/bin/bash
# Run zig commands inside Docker container
# Usage: ./docker-zig.sh [zig args...]
#   ./docker-zig.sh build
#   ./docker-zig.sh build test
#   ./docker-zig.sh version

IMAGE="nxc-zig:dev"

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
    echo "Building Docker image..."
    docker build -t "$IMAGE" .
fi

docker run --rm \
    -v "$(pwd):/workspace" \
    "$IMAGE" \
    "$@"
