# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom;error=true
# Tomcat base image.   Build context = repository root (see docker-bake.hcl).
#
#   tomcat-runtime   distroless java-base + the jlinked JRE (same recipe as java-runtime, plus the
#                    modules Tomcat needs) + an Apache Tomcat tree, with a hardened,
#                    container-shaped configuration baked in (images/tomcat/conf).
#                    Published as tomcat-runtime:<tomcat>-java<java>, e.g. 9.0-java21.
#
# An application image only needs:   COPY app.war /app/webapps/ROOT.war
#
# Layout (all root-owned and read-only for the app user):
#   /opt/jre           the jlinked JRE
#   /opt/tomcat        CATALINA_HOME: Tomcat's code (no scripts, no webapps, no native libs)
#   /opt/tomcat-base   CATALINA_BASE: our conf; drop JDBC drivers into lib/, JNDI contexts into
#                      conf/Catalina/localhost/
#   /app/webapps       appBase: your WAR(s); /tmp is the only writable path (work dir, tmpdir)
ARG JAVA_JDK_IMAGE
ARG JAVA_RUNTIME_BASE
ARG TOMCAT_SOURCE

# The Tomcat tree comes from the official image (Apache checksum + signature verification
# stays upstream), pinned by digest in pins.hcl like everything else.
FROM ${TOMCAT_SOURCE} AS tomcat-src

# --------------------------------------------------------------- assemble ----
FROM ${JAVA_JDK_IMAGE} AS assemble
ARG JAVA_VERSION
# Beyond the java-runtime default list (found with `jdeps` over Tomcat's jars):
#   java.rmi + java.management.rmi   remote JMX, Tomcat's RMI leak protection
#   java.compiler                    Jasper/ECJ compiling JSPs at runtime
ARG JLINK_EXTRA_MODULES="java.rmi,java.management.rmi,java.compiler"
ARG JLINK_MODULES=""
RUN --mount=type=bind,source=scripts/jlink.sh,target=/tmp/jlink.sh \
    sh /tmp/jlink.sh

COPY --from=tomcat-src /usr/local/tomcat /src/home
RUN --mount=type=bind,source=images/tomcat,target=/tmp/tc \
    set -eux; \
    # self-check tool for shell-less health checks
    mkdir /tmp/hc; \
    javac -d /tmp/hc /tmp/tc/HealthCheck.java; \
    jar --create --file /src/home/bin/healthcheck.jar --main-class HealthCheck -C /tmp/hc .; \
    # CATALINA_BASE: our config + the few stock files Tomcat needs next to it
    mkdir -p /src/base/conf/Catalina/localhost /src/base/lib /src/app/webapps; \
    cp /src/home/conf/web.xml /src/home/conf/catalina.properties /src/base/conf/; \
    cp /tmp/tc/conf/server.xml /tmp/tc/conf/logging.properties /tmp/tc/conf/context.xml /src/base/conf/; \
    cp /tmp/tc/jvm.args /src/base/jvm.args; \
    # Strip everything a running service never uses: launch scripts (no shell anyway), the
    # stock webapps (manager/examples/docs), the native connector, ant tasks, translated
    # messages (logs stay English and greppable). LICENSE and NOTICE stay (redistribution).
    h=/src/home; \
    rm -rf "$h"/bin/*.sh "$h"/bin/*.bat "$h"/bin/catalina-tasks.xml "$h"/bin/commons-daemon* \
           "$h"/webapps "$h"/webapps.dist "$h"/native-jni-lib "$h"/conf "$h"/logs "$h"/temp "$h"/work \
           "$h"/BUILDING.txt "$h"/CONTRIBUTING.md "$h"/README.md "$h"/RELEASE-NOTES "$h"/RUNNING.txt \
           "$h"/filtered-KEYS "$h"/upstream-KEYS "$h"/lib/tomcat-i18n-*.jar "$h"/lib/catalina-ant.jar; \
    find /src /opt/jre -type d -exec chmod 0755 {} +; \
    find /src -type f -exec chmod a+r,go-w {} +

# ---------------------------------------------------------------- runtime ----
FROM ${JAVA_RUNTIME_BASE} AS runtime
ARG GIT_SHA=unknown BUILD_DATE=unknown SOURCE_URL=unknown IMAGE_VERSION=unknown

COPY --from=assemble /opt/jre /opt/jre
COPY --from=assemble /src/home /opt/tomcat
COPY --from=assemble /src/base /opt/tomcat-base
COPY --from=assemble /src/app /app

# MaxRAMPercentage=65  - lower than java-runtime's 75: Tomcat adds thread stacks (maxThreads x
#                        ~1 MB), metaspace and direct buffers on top of the heap
# ExitOnOutOfMemoryError, java.io.tmpdir: same reasoning as java-runtime
# Set application flags via JDK_JAVA_OPTIONS (additive), not by replacing this variable.
ENV JAVA_HOME=/opt/jre \
    PATH=/opt/jre/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CATALINA_HOME=/opt/tomcat \
    CATALINA_BASE=/opt/tomcat-base \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=65.0 -XX:+ExitOnOutOfMemoryError -Djava.io.tmpdir=/tmp"

LABEL org.opencontainers.image.title="tomcat-runtime" \
      org.opencontainers.image.description="Distroless + jlinked JRE + hardened Apache Tomcat (nonroot, no shell, read-only friendly)" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${IMAGE_VERSION}"
USER 65532:65532
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["java", "@/opt/tomcat-base/jvm.args", "org.apache.catalina.startup.Bootstrap", "start"]
