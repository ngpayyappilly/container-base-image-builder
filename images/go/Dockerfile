# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom;error=true
# Go base images.   Build context = repository root (see docker-bake.hcl).
#
#   go-build         golang toolchain, unprivileged, reproducible-build defaults
#   go-runtime       distroless/static   - for CGO_ENABLED=0 binaries (default)
#   go-runtime-cgo   distroless/base     - glibc + openssl, for cgo binaries
#
# No default for the upstream refs on purpose: they come from pins.hcl so there
# is exactly one place that decides which digest we trust.
ARG GO_BUILD_IMAGE
ARG GO_RUNTIME_STATIC
ARG GO_RUNTIME_CGO

# ------------------------------------------------------------------ build ----
FROM ${GO_BUILD_IMAGE} AS build

RUN --mount=type=bind,source=scripts/harden.sh,target=/tmp/harden.sh \
    sh /tmp/harden.sh build

# CGO_ENABLED=0   -> static binary that runs on distroless/static
# GOTOOLCHAIN=local -> never silently download another Go toolchain at build time
# -trimpath       -> strips local paths from the binary (reproducible + no info leak)
# -mod=readonly   -> the build may not rewrite go.mod/go.sum behind your back
ENV CGO_ENABLED=0 \
    GOTOOLCHAIN=local \
    GOFLAGS="-trimpath -mod=readonly" \
    GOCACHE=/home/nonroot/.cache/go-build

WORKDIR /src
RUN chown 65532:65532 /src /go && mkdir -p /home/nonroot/.cache && chown -R 65532:65532 /home/nonroot/.cache
USER 65532:65532

# ---------------------------------------------------------------- runtimes ----
FROM ${GO_RUNTIME_STATIC} AS runtime
ARG GIT_SHA=unknown BUILD_DATE=unknown SOURCE_URL=unknown GO_VERSION=unknown
LABEL org.opencontainers.image.title="go-runtime" \
      org.opencontainers.image.description="Distroless static runtime for Go binaries (nonroot, no shell, no package manager)" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${GO_VERSION}"
USER 65532:65532

FROM ${GO_RUNTIME_CGO} AS runtime-cgo
ARG GIT_SHA=unknown BUILD_DATE=unknown SOURCE_URL=unknown GO_VERSION=unknown
LABEL org.opencontainers.image.title="go-runtime-cgo" \
      org.opencontainers.image.description="Distroless base (glibc, libssl) runtime for cgo Go binaries" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${GO_VERSION}"
USER 65532:65532
