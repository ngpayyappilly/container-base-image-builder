// Single build entry point:  docker buildx bake -f docker-bake.hcl -f pins.hcl [target|group]
// (use `make build`). Which versions exist, and the upstream digests, come from the
// generated pins.hcl (VERSIONS, PINS). Everything else is here.
//
// Every image is built once per supported version via a matrix, e.g.
//   go-build-1-26  go-runtime-1-26  go-runtime-cgo-1-26  go-build-1-27 ...
// published as  <registry>/go-build:1.26 , <registry>/java-runtime:21 , ...

variable "REGISTRY" {
  // Where images are published, e.g. ghcr.io/acme or 123456789012.dkr.ecr.eu-west-1.amazonaws.com
  default = "local"
}
variable "GIT_SHA" {
  default = "dev"
}
variable "BUILD_DATE" {
  default = "unknown"
}
variable "SOURCE_URL" {
  default = "https://github.com/ngpayyappilly/container-base-image-builder"
}

// Tags: a floating  :<version>  that is rebuilt weekly (convenient, mutable) and an
// immutable  :<version>-<sha>.  Consumers should pin the digest, not either tag.
// FLOATING_TAGS=false (release candidates): push ONLY the immutable tag. CI tests those exact
// bytes and then promotes the digest to the floating tag (scripts/promote.sh).
variable "FLOATING_TAGS" {
  default = "true"
}
function "tags" {
  params = [name, version]
  result = FLOATING_TAGS == "true" ? [
    "${REGISTRY}/${name}:${version}",
    "${REGISTRY}/${name}:${version}-${GIT_SHA}",
  ] : [
    "${REGISTRY}/${name}:${version}-${GIT_SHA}",
  ]
}

// "1.26" -> "1-26": bake target names may not contain dots.
function "slug" {
  params = [version]
  result = replace(version, ".", "-")
}
function "names" {
  params = [prefix, versions]
  result = [for v in versions : "${prefix}-${slug(v)}"]
}

// ----------------------------------------------------------------- groups ----
// Per language:  `docker buildx bake go`.  Per version: `bake go-build-1-26 go-runtime-1-26`
// (scripts/targets.sh prints these names from "lang[:version]" selectors).
group "default" {
  targets = ["go", "java", "python", "node", "tomcat"]
}
group "go" {
  targets = concat(names("go-build", VERSIONS.go), names("go-runtime", VERSIONS.go), names("go-runtime-cgo", VERSIONS.go))
}
group "java" {
  targets = concat(names("java-build", VERSIONS.java), names("java-runtime", VERSIONS.java))
}
group "python" {
  targets = concat(names("python-build", VERSIONS.python), names("python-runtime", VERSIONS.python))
}
group "node" {
  targets = concat(names("node-build", VERSIONS.node), names("node-runtime", VERSIONS.node))
}

// tomcat-runtime is a (tomcat x java) matrix: tomcat-runtime-9-0-java21 -> tomcat-runtime:9.0-java21
group "tomcat" {
  targets = flatten([for t in VERSIONS.tomcat : [for j in VERSIONS.java : "tomcat-runtime-${slug(t)}-java${j}"]])
}

target "_common" {
  context = "."
  args = {
    GIT_SHA    = GIT_SHA
    BUILD_DATE = BUILD_DATE
    SOURCE_URL = SOURCE_URL
  }
}
// Release builds add docker-bake.ci.hcl on top (multi-arch + SBOM + provenance).

// BuildKit parses every FROM in a Dockerfile, so each target must be handed *all* of
// that language's upstream refs for its version - these functions bundle them.
function "go_args" {
  params = [v]
  result = {
    GO_BUILD_IMAGE    = PINS["go/${v}/build"]
    GO_RUNTIME_STATIC = PINS["go/${v}/runtime"]
    GO_RUNTIME_CGO    = PINS["go/${v}/runtime_cgo"]
    GO_VERSION        = v
  }
}
function "java_args" {
  params = [v]
  result = {
    JAVA_JDK_IMAGE    = PINS["java/${v}/jdk"]
    JAVA_RUNTIME_BASE = PINS["java/${v}/runtime"]
    JAVA_VERSION      = v
  }
}
function "python_args" {
  params = [v]
  result = {
    PYTHON_BUILD_IMAGE  = PINS["python/${v}/build"]
    PYTHON_RUNTIME_BASE = PINS["python/${v}/runtime"]
    UV_IMAGE            = PINS["python/${v}/uv"]
    PYTHON_VERSION      = v
  }
}
function "node_args" {
  params = [v]
  result = {
    NODE_BUILD_IMAGE  = PINS["node/${v}/build"]
    NODE_RUNTIME_BASE = PINS["node/${v}/runtime"]
    NODE_VERSION      = v
  }
}

function "tomcat_args" {
  params = [t, j]
  result = {
    // JDK + distroless base are the java/* pins; only the Tomcat tree has its own pin
    JAVA_JDK_IMAGE    = PINS["java/${j}/jdk"]
    JAVA_RUNTIME_BASE = PINS["java/${j}/runtime"]
    TOMCAT_SOURCE     = PINS["tomcat/${t}/source"]
    JAVA_VERSION      = j
    IMAGE_VERSION     = "${t}-java${j}"
  }
}

// -------------------------------------------------------------------- Go ----
target "go-build" {
  name       = "go-build-${slug(v)}"
  matrix     = { v = VERSIONS.go }
  inherits   = ["_common"]
  dockerfile = "images/go/Dockerfile"
  target     = "build"
  args       = go_args(v)
  tags       = tags("go-build", v)
}
target "go-runtime" {
  name       = "go-runtime-${slug(v)}"
  matrix     = { v = VERSIONS.go }
  inherits   = ["_common"]
  dockerfile = "images/go/Dockerfile"
  target     = "runtime"
  args       = go_args(v)
  tags       = tags("go-runtime", v)
}
target "go-runtime-cgo" {
  name       = "go-runtime-cgo-${slug(v)}"
  matrix     = { v = VERSIONS.go }
  inherits   = ["_common"]
  dockerfile = "images/go/Dockerfile"
  target     = "runtime-cgo"
  args       = go_args(v)
  tags       = tags("go-runtime-cgo", v)
}

// ------------------------------------------------------------------ Java ----
target "java-build" {
  name       = "java-build-${slug(v)}"
  matrix     = { v = VERSIONS.java }
  inherits   = ["_common"]
  dockerfile = "images/java/Dockerfile"
  target     = "build"
  args       = java_args(v)
  tags       = tags("java-build", v)
}
target "java-runtime" {
  name       = "java-runtime-${slug(v)}"
  matrix     = { v = VERSIONS.java }
  inherits   = ["_common"]
  dockerfile = "images/java/Dockerfile"
  target     = "runtime"
  args       = java_args(v)
  tags       = tags("java-runtime", v)
}

// ---------------------------------------------------------------- Python ----
target "python-build" {
  name       = "python-build-${slug(v)}"
  matrix     = { v = VERSIONS.python }
  inherits   = ["_common"]
  dockerfile = "images/python/Dockerfile"
  target     = "build"
  args       = python_args(v)
  tags       = tags("python-build", v)
}
target "python-runtime" {
  name       = "python-runtime-${slug(v)}"
  matrix     = { v = VERSIONS.python }
  inherits   = ["_common"]
  dockerfile = "images/python/Dockerfile"
  target     = "runtime"
  args       = python_args(v)
  tags       = tags("python-runtime", v)
}

// ------------------------------------------------------------------ Node ----
target "node-build" {
  name       = "node-build-${slug(v)}"
  matrix     = { v = VERSIONS.node }
  inherits   = ["_common"]
  dockerfile = "images/node/Dockerfile"
  target     = "build"
  args       = node_args(v)
  tags       = tags("node-build", v)
}
target "node-runtime" {
  name       = "node-runtime-${slug(v)}"
  matrix     = { v = VERSIONS.node }
  inherits   = ["_common"]
  dockerfile = "images/node/Dockerfile"
  target     = "runtime"
  args       = node_args(v)
  tags       = tags("node-runtime", v)
}

// ---------------------------------------------------------------- Tomcat ----
target "tomcat-runtime" {
  name       = "tomcat-runtime-${slug(t)}-java${j}"
  matrix     = { t = VERSIONS.tomcat, j = VERSIONS.java }
  inherits   = ["_common"]
  dockerfile = "images/tomcat/Dockerfile"
  target     = "runtime"
  args       = tomcat_args(t, j)
  tags       = tags("tomcat-runtime", "${t}-java${j}")
}
