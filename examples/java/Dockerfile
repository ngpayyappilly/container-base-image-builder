# syntax=docker/dockerfile:1
# Example application consuming the Java base images.
# In real projects pin these to digests:  .../java-build:25@sha256:...
ARG BUILD_IMAGE=ghcr.io/ngpayyappilly/java-build:25
ARG RUNTIME_IMAGE=ghcr.io/ngpayyappilly/java-runtime:25

FROM ${BUILD_IMAGE} AS build

# With Maven/Gradle the same two-layer idea applies - resolve deps first, then compile:
#   COPY --chown=65532:65532 .mvn mvnw pom.xml ./
#   RUN --mount=type=cache,target=/home/nonroot/.m2,uid=65532,gid=65532 ./mvnw -B dependency:go-offline
#   COPY --chown=65532:65532 src src
#   RUN --mount=type=cache,target=/home/nonroot/.m2,uid=65532,gid=65532 ./mvnw -B -o package -DskipTests
COPY --chown=65532:65532 src src
RUN javac -d classes src/Main.java && \
    jar --create --file app.jar --main-class Main -C classes .

FROM ${RUNTIME_IMAGE}
COPY --from=build /src/app.jar /app/app.jar
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["java", "-jar", "/app/app.jar", "healthcheck"]
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
