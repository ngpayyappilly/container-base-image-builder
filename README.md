# Hardened base images: Go · Java · Python · Node

One repo, one build entry point, one hardening recipe, four languages. Every language
ships **two images**: a `*-build` image (toolchain, throw-away) and a `*-runtime` image
(the only thing that reaches production).

| Image | Built from | Size | Shell | Notes |
|---|---|---|---|---|
| `go-build` | `golang:1.26-trixie` | 892 MB | yes | `CGO_ENABLED=0`, `GOTOOLCHAIN=local`, `-trimpath` |
| `go-runtime` | `distroless/static-debian13` | **2.4 MB** | no | static binaries |
| `go-runtime-cgo` | `distroless/base-debian13` | 35 MB | no | cgo binaries (glibc, libssl) |
| `java-build` | `eclipse-temurin:25-jdk-noble` | 423 MB | yes | bring Maven/Gradle via your wrapper |
| `java-runtime` | `distroless/java-base-debian13` + **jlinked JRE** | 134 MB | no | CDS archive, cacerts bundled |
| `python-build` | `python:3.14-trixie` + `uv` | 1.17 GB | yes | deps go to a relocatable `/opt/venv` |
| `python-runtime` | `python:3.14-slim-trixie`, hardened | 146 MB | `sh` only | no pip/apt/setuid, `tini` as PID 1 |
| `node-build` | `node:24-trixie` | 1.24 GB | yes | corepack on, quiet npm |
| `node-runtime` | `distroless/nodejs24-debian13` | 162 MB | no | `NODE_ENV=production` |

All images: Debian 13 "trixie" userspace, `linux/amd64` + `linux/arm64`, run as numeric
**uid/gid 65532** (the distroless `nonroot` id, so one `runAsUser` and one `--chown` everywhere).

## Quick start

```bash
make build        # build all 9 images locally (REGISTRY=local)
make test         # + assert hardening invariants + build & run every example
make scan         # Trivy gate: runtime images must have 0 fixable HIGH/CRITICAL
make lint         # hadolint + shellcheck
make pins         # re-resolve upstream tags to digests (pins.hcl)
```

Consuming an image (full examples in [examples/](examples)):

```dockerfile
FROM ghcr.io/acme/go-build:1.26@sha256:... AS build      # pin YOUR deps on OUR digest
COPY --chown=65532:65532 go.mod go.sum ./                # 1. dependency layer (rarely changes)
RUN --mount=type=cache,target=/go/pkg/mod,uid=65532,gid=65532 go mod download
COPY --chown=65532:65532 . .                             # 2. source layer (changes every commit)
RUN go build -o /src/app .

FROM ghcr.io/acme/go-runtime:1.26@sha256:...
COPY --from=build /src/app /app
ENTRYPOINT ["/app"]
```

## How it's layered

```
 upstream (pinned by digest in pins.hcl)
 ├─ golang:1.26-trixie ──────────► go-build            └─ distroless/static ──► go-runtime
 ├─ temurin:25-jdk ─┬─ jlink ────► (JRE /opt/jre) ──┐   └─ distroless/base ────► go-runtime-cgo
 │                  └────────────► java-build       └─► distroless/java-base ──► java-runtime
 ├─ python:3.14-trixie + uv ─────► python-build ─ /opt/venv ─┐
 │  python:3.14-slim-trixie ─ harden.sh ─────────────────────┴► python-runtime
 └─ node:24-trixie ──────────────► node-build           └─ distroless/nodejs ──► node-runtime

 your app image = <lang>-build (compile)  ──COPY --from──►  <lang>-runtime (ship)
```

Layering rules the repo follows (and your app images should too):

1. **Order layers by change frequency**: OS/runtime (monthly) → dependencies (weekly) → your code (every commit). Anything that changes often goes last, so everything above stays cached and, in the registry, shared between versions.
2. **Multi-stage always**: compilers, package managers, caches and source never exist in the shipped image.
3. **One `RUN` per concern, cleaned in the same layer**: files deleted in a *later* layer still ship; `harden.sh` installs, patches and cleans in one layer.
4. **Cache mounts, not cache layers**: `--mount=type=cache` (Go modules, `~/.m2`, `uv`, `npm`) keeps downloads out of every layer yet makes rebuilds fast.
5. **Bind-mount build helpers**: `scripts/harden.sh` is mounted, not `COPY`'d, so it isn't left in an image layer.
6. **Tight build context**: `.dockerignore` is allow-list style (`*` then `!images/`), so secrets or `.git` can never reach a layer.
7. **Same minor in build and runtime** (Python): guarantees the venv's interpreter symlink and C-extension ABI match.

## Hardening checklist: what, and where

| Practice | Implemented in |
|---|---|
| Base images pinned by **multi-arch index digest**, tag kept for humans | [pins.tsv](pins.tsv) → [pins.hcl](pins.hcl) (generated) |
| Pins refreshed automatically, reviewed through CI | [refresh-pins.yml](.github/workflows/refresh-pins.yml) |
| Minimal runtime: distroless (Go, Java, Node), stripped slim (Python) | `images/*/Dockerfile` |
| Custom **jlink** JRE: only the modules you list; `--strip-debug`, zip compression, AppCDS | [images/java/Dockerfile](images/java/Dockerfile) |
| Non-root, **numeric** `USER 65532:65532` (works with `runAsNonRoot`) | every Dockerfile |
| OS packages patched on every build (`apt-get upgrade`) | [harden.sh](scripts/harden.sh) |
| setuid/setgid bits stripped | `harden.sh` |
| No `apt`/`dpkg`/`su`/`mount`/`passwd` in runtime; root locked; `dpkg/status` kept so scanners still work | `harden.sh runtime` |
| `pip`, `setuptools`, `ensurepip`, `tkinter`… removed from Python runtime | [images/python/Dockerfile](images/python/Dockerfile) |
| Licence files kept when docs are stripped (redistribution requirement) | `harden.sh` |
| `tini` as PID 1 (signal forwarding, zombie reaping) | python-runtime |
| JVM container-aware: `MaxRAMPercentage`, `ExitOnOutOfMemoryError`, tmp dir for `--read-only` | java-runtime `ENV` |
| No surprise toolchain downloads (`GOTOOLCHAIN=local`, `UV_PYTHON_DOWNLOADS=never`) | build images |
| Reproducible-ish builds (`-trimpath`, `-mod=readonly`, `uv sync --frozen`, `npm ci`, `--ignore-scripts`) | build images / examples |
| Precompiled bytecode so the read-only runtime never writes (`UV_COMPILE_BYTECODE`, `PYTHONDONTWRITEBYTECODE`) | python images |
| OCI labels: source, revision, created, version | every runtime `LABEL` |
| Self-healthchecks for shell-less images (`/app healthcheck`) | [examples/](examples) |
| Lint (hadolint, shellcheck, BuildKit `check=error=true`) | `make lint`, Dockerfile header |
| Vulnerability **gate** on runtime images (Trivy, fixable HIGH/CRITICAL) | [scan.sh](scripts/scan.sh) |
| Behavioural verification of the invariants above | [verify.sh](scripts/verify.sh) |
| Every example runs under `--read-only --cap-drop ALL --no-new-privileges` | [smoke-test.sh](scripts/smoke-test.sh) |
| Multi-arch, **SBOM + max provenance** attestations, **keyless cosign** signature per digest | [build.yml](.github/workflows/build.yml), [docker-bake.ci.hcl](docker-bake.ci.hcl) |
| Workflow least-privilege, actions pinned by SHA, weekly rebuild for OS patches | `build.yml` |

### Run-time settings to pair with these images

The image can only do so much; the platform enforces the rest.

```bash
docker run --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
           --pids-limit 200 --memory 512m  my-app
```

```yaml
# Kubernetes
securityContext:                      # container level
  runAsNonRoot: true
  runAsUser: 65532
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: { drop: [ALL] }
  seccompProfile: { type: RuntimeDefault }
volumes: [{ name: tmp, emptyDir: { medium: Memory } }]   # mount at /tmp
```

## Operating it

* **Weekly**: `refresh-pins` opens a PR with new upstream digests (new Go/JDK/Node/Python patch releases); `build.yml` rebuilds and republishes on a schedule so Debian security fixes land even without a code change.
* **New language major** (`node:24` → `node:26`): edit [pins.tsv](pins.tsv), `make pins`, `make test`. Image tags follow the version (`node-runtime:26`), so teams migrate on their own schedule. To support two majors at once, add a second `VAR` set in `pins.tsv` and a second set of bake targets.
* **Consumers** should pin `image:tag@sha256:…` and let Renovate/Dependabot bump it; `:<major>` is a convenience tag that moves weekly.
* **Verify a pulled image**: `cosign verify --certificate-identity-regexp 'https://github.com/<org>/<repo>/' --certificate-oidc-issuer https://token.actions.githubusercontent.com <image>@<digest>`
* **Debugging shell-less images**: `kubectl debug -it <pod> --image=busybox --target=<container>` or `docker debug`. Don't add a shell to production images.

## Setup checklist (placeholders to fill in)

1. `git init`, then replace `ngpayyappilly` in [docker-bake.hcl](docker-bake.hcl) (`SOURCE_URL`) and the example Dockerfiles (`ghcr.io/ngpayyappilly/...`). `REGISTRY` is set by CI (`ghcr.io/<owner>`); for ECR change the login step in `build.yml`.
2. Make the first publish, then pin your app images to the resulting digests.

## Trade-offs and known limitations

* **Python runtime is hardened-slim, not distroless.** `distroless/python3` ships Debian's own Python version and can't take extra system libs. The cost: a `sh` and ~146 MB. If your services are pure-Python wheels and you accept Debian's version, switching is a small change.
* **The JRE is jlinked from Temurin on Ubuntu 24.04 and run on Debian 13 distroless.** glibc is backwards-compatible and this is exercised by `make test`, but it's two distros; if you want one, swap `JAVA_JDK_IMAGE` for a trixie-based JDK. The default module list includes `java.desktop` because Spring/Jackson use `java.beans`; trim it per app with `jdeps`. On JDK ≤ 21 also add `jdk.crypto.ec`.
* **`JAVA_TOOL_OPTIONS` prints `Picked up JAVA_TOOL_OPTIONS…` to stderr** on every JVM start (including healthchecks). Harmless; move the flags into your `ENTRYPOINT` if the noise matters.
* **Build images are not gated on CVEs, only reported.** Findings there are in upstream-bundled tooling (e.g. npm/corepack internals) and never ship; runtime images are gated hard.
* **No hardened-OS vendor (Chainguard, Wolfi, Docker Hardened Images).** They give faster CVE turnaround than self-patching Debian, at a licensing/lock-in cost. Worth evaluating once volume justifies it; this repo's `pins.tsv` is the only place you'd change.
* **Tested here:** all 9 images built natively on linux/arm64 (Docker Desktop), `make lint`/`test`/`scan` green. **Not tested here:** the GitHub Actions workflows (multi-arch/QEMU build, push, cosign) have never run, so expect to fix small things on their first execution.
