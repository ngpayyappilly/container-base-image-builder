# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom;error=true
# Python base images.   Build context = repository root (see docker-bake.hcl).
#
#   python-build     full Debian python (compilers, headers) + uv, unprivileged.
#                    Installs dependencies into a relocatable venv at /opt/venv.
#   python-runtime   python slim, hardened by scripts/harden.sh: patched, no apt/dpkg,
#                    no pip, no setuid, root locked, tini as PID 1, nonroot user.
#
# Why not distroless/python3? It ships Debian's own python (not a version we pick)
# and has no way to add system libs. Using the same python:X.Y minor in build and
# runtime guarantees the venv's interpreter symlink and C-extension ABI match.
ARG PYTHON_BUILD_IMAGE
ARG PYTHON_RUNTIME_BASE
ARG UV_IMAGE

FROM ${UV_IMAGE} AS uv

# ------------------------------------------------------------------ build ----
FROM ${PYTHON_BUILD_IMAGE} AS build

RUN --mount=type=bind,source=scripts/harden.sh,target=/tmp/harden.sh \
    sh /tmp/harden.sh build

COPY --from=uv /uv /uvx /usr/local/bin/

# UV_LINK_MODE=copy          - cache mount and venv are on different filesystems
# UV_COMPILE_BYTECODE=1      - ship .pyc so the read-only runtime never needs to write
# UV_PYTHON_DOWNLOADS=never  - use the image's interpreter, never fetch another
# UV_PROJECT_ENVIRONMENT     - venv lives outside the source tree; copied to runtime
ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN mkdir -p /opt/venv /src /home/nonroot/.cache && \
    chown -R 65532:65532 /opt/venv /src /home/nonroot/.cache
WORKDIR /src
USER 65532:65532

# ---------------------------------------------------------------- runtime ----
FROM ${PYTHON_RUNTIME_BASE} AS runtime
ARG GIT_SHA=unknown BUILD_DATE=unknown SOURCE_URL=unknown PYTHON_VERSION=unknown

# tini: reaps zombies and forwards SIGTERM so `docker stop` is graceful.
RUN --mount=type=bind,source=scripts/harden.sh,target=/tmp/harden.sh \
    EXTRA_PACKAGES="tini" sh /tmp/harden.sh runtime && \
    # The runtime never installs anything: remove pip & friends (a frequent CVE
    # source and a supply-chain foothold) plus modules a service never imports.
    rm -rf /usr/local/bin/pip* /usr/local/bin/idle* /usr/local/bin/pydoc* \
           /usr/local/lib/python3*/site-packages/pip* \
           /usr/local/lib/python3*/site-packages/setuptools* \
           /usr/local/lib/python3*/site-packages/wheel* \
           /usr/local/lib/python3*/site-packages/_distutils_hack \
           /usr/local/lib/python3*/site-packages/distutils-precedence.pth \
           /usr/local/lib/python3*/ensurepip /usr/local/lib/python3*/idlelib \
           /usr/local/lib/python3*/turtledemo /usr/local/lib/python3*/tkinter

ENV PATH=/opt/venv/bin:$PATH \
    VIRTUAL_ENV=/opt/venv \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1

LABEL org.opencontainers.image.title="python-runtime" \
      org.opencontainers.image.description="Hardened python slim (nonroot, no pip/apt, tini PID 1)" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${PYTHON_VERSION}"
USER 65532:65532
WORKDIR /app
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python3"]
