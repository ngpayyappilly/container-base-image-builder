# syntax=docker/dockerfile:1
# Example application consuming the Node base images.
# In real projects pin these to digests:  .../node-build:24@sha256:...
ARG BUILD_IMAGE=ghcr.io/ngpayyappilly/node-build:24
ARG RUNTIME_IMAGE=ghcr.io/ngpayyappilly/node-runtime:24

FROM ${BUILD_IMAGE} AS build

# Layer 1 - production deps. Only invalidated by package*.json changes.
# npm ci = exact lockfile install; --ignore-scripts = a compromised dependency's
# postinstall hook cannot run during the build (run `npm rebuild <pkg>` for the
# few packages that genuinely need a native build step).
COPY --chown=65532:65532 package.json package-lock.json ./
RUN --mount=type=cache,target=/home/nonroot/.npm,uid=65532,gid=65532 \
    npm ci --omit=dev --ignore-scripts

FROM ${RUNTIME_IMAGE}
# Layer 2 - node_modules (rare); Layer 3 - your code (constant).
COPY --from=build /src/node_modules ./node_modules
COPY package.json server.js ./
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["/nodejs/bin/node", "server.js", "healthcheck"]
CMD ["server.js"]
