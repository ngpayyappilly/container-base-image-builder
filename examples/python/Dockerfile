# syntax=docker/dockerfile:1
# Example application consuming the Python base images.
# In real projects pin these to digests:  .../python-build:3.14@sha256:...
ARG BUILD_IMAGE=ghcr.io/ngpayyappilly/python-build:3.14
ARG RUNTIME_IMAGE=ghcr.io/ngpayyappilly/python-runtime:3.14

FROM ${BUILD_IMAGE} AS build

# Layer 1 - third-party deps into /opt/venv. Only invalidated by lockfile changes.
# --frozen: fail if uv.lock is out of date instead of silently re-resolving.
COPY --chown=65532:65532 pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/home/nonroot/.cache/uv,uid=65532,gid=65532 \
    uv sync --frozen --no-dev

FROM ${RUNTIME_IMAGE}
# Layer 2 - the venv (changes rarely); Layer 3 - your code (changes constantly).
COPY --from=build /opt/venv /opt/venv
COPY app/ /app/app/
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["python", "app/main.py", "healthcheck"]
CMD ["python", "app/main.py"]
