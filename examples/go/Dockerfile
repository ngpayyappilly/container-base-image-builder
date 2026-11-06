# syntax=docker/dockerfile:1
# Example application consuming the Go base images.
# In real projects pin these to digests:  .../go-build:1.27@sha256:...
ARG BUILD_IMAGE=ghcr.io/ngpayyappilly/go-build:1.27
ARG RUNTIME_IMAGE=ghcr.io/ngpayyappilly/go-runtime:1.27

FROM ${BUILD_IMAGE} AS build

# Layer 1 - dependencies. Only invalidated when go.mod / go.sum change.
COPY --chown=65532:65532 go.mod go.sum* ./
RUN --mount=type=cache,target=/go/pkg/mod,uid=65532,gid=65532 \
    go mod download

# Layer 2 - source. Changes on every commit, but deps above stay cached.
COPY --chown=65532:65532 . .
RUN --mount=type=cache,target=/go/pkg/mod,uid=65532,gid=65532 \
    --mount=type=cache,target=/home/nonroot/.cache/go-build,uid=65532,gid=65532 \
    go build -ldflags="-s -w" -o /src/app .

FROM ${RUNTIME_IMAGE}
COPY --from=build /src/app /app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
