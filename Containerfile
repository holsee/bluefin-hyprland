# Build context: scripts and static files, referenced by bind-mount so they are
# never copied into the final image.
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base: Bluefin, NVIDIA open-kernel-module flavour, tracking the stable channel.
#
# Deliberately a tag rather than a digest. The daily scheduled build then picks
# up each new Bluefin release automatically, which is the whole point of a
# tracking image. Pin to @sha256:... instead if you want to gate base bumps.
FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Verify the result is a valid bootc image.
RUN bootc container lint
