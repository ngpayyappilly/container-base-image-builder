# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom;error=true
# Java base images.   Build context = repository root (see docker-bake.hcl).
#
#   java-build     Temurin JDK, unprivileged. Bring your own Maven/Gradle via the
#                  project wrapper (mvnw / gradlew) so versions live in your repo.
#   java-runtime   distroless java-base (glibc only, no JVM) + a *jlinked* JRE that
#                  contains only the modules listed in JLINK_MODULES. ~60% smaller
#                  than a full JRE and far less attack surface.
ARG JAVA_JDK_IMAGE
ARG JAVA_RUNTIME_BASE

# ---------------------------------------------------------- jlink the JRE ----
FROM ${JAVA_JDK_IMAGE} AS jre-builder
ARG JAVA_VERSION
# Module list, per-LTS jlink differences and the cacerts fix live in scripts/jlink.sh (shared
# with images/tomcat). Override with --build-arg JLINK_MODULES=... or add to the default
# list with --build-arg JLINK_EXTRA_MODULES=java.rmi,...
ARG JLINK_MODULES=""
ARG JLINK_EXTRA_MODULES=""
RUN --mount=type=bind,source=scripts/jlink.sh,target=/tmp/jlink.sh \
    sh /tmp/jlink.sh

# ------------------------------------------------------------------ build ----
FROM ${JAVA_JDK_IMAGE} AS build
RUN --mount=type=bind,source=scripts/harden.sh,target=/tmp/harden.sh \
    sh /tmp/harden.sh build
WORKDIR /src
RUN chown 65532:65532 /src
USER 65532:65532

# ---------------------------------------------------------------- runtime ----
FROM ${JAVA_RUNTIME_BASE} AS runtime
ARG GIT_SHA=unknown BUILD_DATE=unknown SOURCE_URL=unknown JAVA_VERSION=unknown

# root-owned and therefore read-only for the app user
COPY --from=jre-builder /opt/jre /opt/jre

# MaxRAMPercentage        - size the heap from the cgroup limit, not the host
# ExitOnOutOfMemoryError  - die and let the orchestrator restart; a JVM that
#                           survived an OOM is in an undefined state
# -Djava.io.tmpdir        - works with --read-only + a tmpfs on /tmp
ENV JAVA_HOME=/opt/jre \
    PATH=/opt/jre/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError -Djava.io.tmpdir=/tmp"

LABEL org.opencontainers.image.title="java-runtime" \
      org.opencontainers.image.description="Distroless + jlinked JRE (nonroot, no shell, no package manager)" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${JAVA_VERSION}"
USER 65532:65532
WORKDIR /app
