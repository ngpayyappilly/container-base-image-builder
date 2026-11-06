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
# java.desktop is here because Spring/Jackson/etc. use java.beans. Drop it if you
# know you don't. Add jdk.localedata for non-English locales.
# Per-app minimum:  jdeps --print-module-deps --ignore-missing-deps app.jar
ARG JLINK_MODULES="java.base,java.logging,java.xml,java.naming,java.sql,java.management,java.net.http,java.security.jgss,java.security.sasl,java.instrument,java.prefs,java.transaction.xa,java.desktop,jdk.unsupported,jdk.zipfs,jdk.httpserver,jdk.management,jdk.management.agent,jdk.jfr,jdk.naming.dns,jdk.crypto.cryptoki,jdk.charsets"
# Per-LTS differences:
#   17      --compress=2 (the zip-N spelling arrived in 21); jdk.crypto.ec is a separate module
#   21      zip-6; jdk.crypto.ec is still a separate module (merged into java.base in 22)
#   25+     zip-6; nothing extra
RUN set -eux; \
    case "${JAVA_VERSION}" in \
      17) compress=2;      modules="${JLINK_MODULES},jdk.crypto.ec" ;; \
      21) compress=zip-6;  modules="${JLINK_MODULES},jdk.crypto.ec" ;; \
      *)  compress=zip-6;  modules="${JLINK_MODULES}" ;; \
    esac; \
    jlink \
      --add-modules "${modules}" \
      --strip-debug --no-header-files --no-man-pages \
      --compress="${compress}" \
      --generate-cds-archive \
      --output /opt/jre; \
    # Temurin-on-Ubuntu symlinks cacerts into /etc/ssl; materialise the real file
    # so the trust store travels with the JRE into the distroless image.
    cp --dereference --remove-destination \
       "$JAVA_HOME/lib/security/cacerts" /opt/jre/lib/security/cacerts; \
    /opt/jre/bin/java -version

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
