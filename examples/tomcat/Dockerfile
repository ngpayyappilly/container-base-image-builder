# syntax=docker/dockerfile:1
# Example application consuming the Tomcat base image: a legacy-style WAR.
# In real projects pin these to digests:  .../tomcat-runtime:9.0-java21@sha256:...
ARG BUILD_IMAGE=ghcr.io/ngpayyappilly/java-build:21
ARG RUNTIME_IMAGE=ghcr.io/ngpayyappilly/tomcat-runtime:9.0-java21

FROM ${BUILD_IMAGE} AS build
# Your real build produces the WAR (Maven/Gradle via the project wrapper, as in the java example):
#   COPY --chown=65532:65532 .mvn mvnw pom.xml ./
#   RUN --mount=type=cache,target=/home/nonroot/.m2,uid=65532,gid=65532 ./mvnw -B dependency:go-offline
#   COPY --chown=65532:65532 src src
#   RUN --mount=type=cache,target=/home/nonroot/.m2,uid=65532,gid=65532 ./mvnw -B -o package -DskipTests
# Here the "application" is one JSP, which also proves Tomcat can compile JSPs on a read-only fs.
COPY --chown=65532:65532 webapp webapp
RUN jar --create --file app.war -C webapp .

FROM ${RUNTIME_IMAGE}
# The whole integration. The WAR runs from the archive (unpackWARs=false) so a read-only root
# filesystem works. Need an exploded webapp (getRealPath()/file writes)? Explode in the build
# stage and COPY the directory to /app/webapps/ROOT/ instead.
COPY --from=build --chmod=0644 /src/app.war /app/webapps/ROOT.war
# JDBC drivers:      COPY driver.jar /opt/tomcat-base/lib/
# JNDI datasources:  COPY ROOT.xml /opt/tomcat-base/conf/Catalina/localhost/
# Tuning:            ENV JDK_JAVA_OPTIONS="-Dtomcat.maxThreads=300"
HEALTHCHECK --interval=30s --timeout=3s CMD ["java", "-cp", "/opt/tomcat/bin/healthcheck.jar", "HealthCheck"]
