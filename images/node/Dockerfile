# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom;error=true
# Node base images.   Build context = repository root (see docker-bake.hcl).
#
#   node-build     full Debian node (python3, make, g++ for native addons),
#                  unprivileged, corepack enabled for pnpm/yarn.
#   node-runtime   distroless nodejs (nonroot, no shell, no npm, no package manager).
#                  ENTRYPOINT is already `node`, so apps only set CMD ["server.js"].
ARG NODE_BUILD_IMAGE
ARG NODE_RUNTIME_BASE

# ------------------------------------------------------------------ build ----
FROM ${NODE_BUILD_IMAGE} AS build

RUN --mount=type=bind,source=scripts/harden.sh,target=/tmp/harden.sh \
    sh /tmp/harden.sh build

# Quiet, deterministic, no network chatter during builds.
ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_CACHE=/home/nonroot/.npm \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    COREPACK_HOME=/home/nonroot/.cache/corepack

RUN corepack enable && \
    mkdir -p /src /home/nonroot/.npm /home/nonroot/.cache && \
    chown -R 65532:65532 /src /home/nonroot/.npm /home/nonroot/.cache
WORKDIR /src
USER 65532:65532

# ---------------------------------------------------------------- runtime ----
FROM ${NODE_RUNTIME_BASE} AS runtime
ARG GIT_SHA=unknown BUILD_DATE=unknown SOURCE_URL=unknown NODE_VERSION=unknown
# NODE_ENV=production switches Express & co. to their fast, non-verbose paths.
ENV NODE_ENV=production
LABEL org.opencontainers.image.title="node-runtime" \
      org.opencontainers.image.description="Distroless Node.js runtime (nonroot, no shell, no npm)" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${NODE_VERSION}"
USER 65532:65532
WORKDIR /app
