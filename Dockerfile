FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl xz-utils ca-certificates nodejs npm \
    && rm -rf /var/lib/apt/lists/*

ARG ZIG_VERSION=0.16.0
RUN ARCH=$(uname -m | sed 's/x86_64/x86_64/' | sed 's/aarch64/aarch64/') \
    && if [ "$ARCH" = "x86_64" ]; then ZIG_ARCH="x86_64-linux"; else ZIG_ARCH="aarch64-linux"; fi \
    && curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
    && tar -xJf /tmp/zig.tar.xz -C /usr/local \
    && ln -s "/usr/local/zig-${ZIG_ARCH}-${ZIG_VERSION}/zig" /usr/local/bin/zig \
    && rm /tmp/zig.tar.xz

WORKDIR /workspace
ENV NXC_DOCKER=1

ENTRYPOINT ["zig"]
CMD ["version"]
