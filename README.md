# Hardened base images: Go · Java · Python · Node

One repo, one build entry point, one hardening recipe, four languages, **several versions
of each**. Every language ships a `*-build` image (toolchain, throw-away) and a `*-runtime`
image (the only thing that reaches production) **per supported version**, plus a
`tomcat-runtime` for legacy servlet applications: 27 images in total.
The image tag is the language version: `java-runtime:21`, `node-build:24`, `go-runtime:1.27`
(`tomcat-runtime` is tagged `<tomcat>-java<java>`: `tomcat-runtime:9.0-java21`).

## Supported versions

| Language | Versions | Policy |
|---|---|---|
| Java | **17, 21, 25** | the three current LTS releases |
| Node | **22, 24, 26** | LTS lines (even majors; 26 entered LTS in Oct 2026) |
| Go | **1.26, 1.27** | no LTS exists; the two releases Go itself supports |
| Python | **3.12, 3.13, 3.14** | no LTS exists; the supported releases with at least ~1 year of life left |
| Tomcat | **9.0** × Java 17, 21, 25 | the `javax.*` line most existing apps still use; add 10.1 (`jakarta.*`) per [pins.tsv](pins.tsv) once an app is migrated |

Versions come from [pins.tsv](pins.tsv) (EOL dates are in its header). Retire a version
about 6 months before its upstream EOL so consumers have time to migrate.

| Image | Built from | Size (per version) | Shell | Notes |
|---|---|---|---|---|
| `go-build` | `golang:<v>-trixie` | 892 / 902 MB | yes | `CGO_ENABLED=0`, `GOTOOLCHAIN=local`, `-trimpath` |
| `go-runtime` | `distroless/static-debian13` | **2.4 MB** | no | static binaries |
| `go-runtime-cgo` | `distroless/base-debian13` | 35 MB | no | cgo binaries (glibc, libssl) |
| `java-build` | `eclipse-temurin:<v>-jdk-noble` | 462 / 488 / 429 MB | yes | bring Maven/Gradle via your wrapper |
| `java-runtime` | `distroless/java-base-debian13` + **jlinked JRE** | 121 / 131 / 134 MB | no | CDS archive, cacerts bundled |
| `python-build` | `python:<v>-trixie` + `uv` | 1.16-1.17 GB | yes | deps go to a relocatable `/opt/venv` |
| `python-runtime` | `python:<v>-slim-trixie`, hardened | 145-146 MB | `sh` only | no pip/apt/setuid, `tini` as PID 1 |
| `node-build` | `node:<v>-trixie` | 1.24 / 1.24 / 1.26 GB | yes | corepack on (installed from npm on Node ≥ 25), quiet npm |
| `node-runtime` | `distroless/nodejs<v>-debian13` | 161 / 162 / 189 MB | no | `NODE_ENV=production` |
| `tomcat-runtime` | `distroless/java-base-debian13` + **jlinked JRE** + Tomcat tree | 119 / 130 / 135 MB (Java 17/21/25) | no | hardened config baked in, runs from a read-only rootfs |

(Multiple sizes are listed in version order: Go 1.26/1.27, Java 17/21/25, Node 22/24/26.)

All images: Debian 13 "trixie" userspace (the JDK stage is Ubuntu 24.04, see trade-offs),
`linux/amd64` + `linux/arm64`, run as numeric **uid/gid 65532** (the distroless `nonroot`
id, so one `runAsUser` and one `--chown` everywhere).

## Quick start

```bash
make build        # build all 27 images locally (REGISTRY=local)
make test         # + assert hardening invariants + build & run every example, per version
make scan         # Trivy gate: runtime images must have 0 fixable HIGH/CRITICAL
make lint         # hadolint + shellcheck
make pins         # re-resolve upstream tags to digests (pins.hcl)

# any of build/test/scan can be narrowed:
make test ONLY=java                  # one language, all its versions
make test ONLY="java:21 go:1.27"     # specific versions
make test ONLY=tomcat:9.0-java21     # tomcat versions are <tomcat>-java<java>
```

Consuming an image (full examples in [examples/](examples)):

```dockerfile
FROM ghcr.io/ngpayyappilly/go-build:1.27@sha256:... AS build   # pin YOUR deps on OUR digest
COPY --chown=65532:65532 go.mod go.sum ./                # 1. dependency layer (rarely changes)
RUN --mount=type=cache,target=/go/pkg/mod,uid=65532,gid=65532 go mod download
COPY --chown=65532:65532 . .                             # 2. source layer (changes every commit)
RUN go build -o /src/app .

FROM ghcr.io/ngpayyappilly/go-runtime:1.27@sha256:...
COPY --from=build /src/app /app
ENTRYPOINT ["/app"]
```

### Legacy Tomcat apps

`tomcat-runtime` is distroless + the same jlinked JRE as `java-runtime` + an Apache Tomcat tree with
a hardened, container-shaped configuration baked in. An application image is one `COPY`:

```dockerfile
FROM ghcr.io/ngpayyappilly/tomcat-runtime:9.0-java21@sha256:...
COPY app.war /app/webapps/ROOT.war
```

Full example (builds a WAR with `java-build`, runs under `--read-only --cap-drop ALL`): [examples/tomcat](examples/tomcat).

| You want | You do |
|---|---|
| JDBC driver | `COPY driver.jar /opt/tomcat-base/lib/` |
| JNDI datasource | `COPY ROOT.xml /opt/tomcat-base/conf/Catalina/localhost/` (or `META-INF/context.xml` in the WAR) |
| Tune the connector | `ENV JDK_JAVA_OPTIONS="-Dtomcat.maxThreads=300"` (also `acceptCount`, `connectionTimeout`, `maxPostSize`). Additive: do **not** set `JAVA_TOOL_OPTIONS`, it holds the memory defaults and would be replaced |
| Secrets | mount a Secret as a file, or pass `-D` properties; JVM arguments are deliberately **not** logged at startup |
| An exploded webapp (`getRealPath()`, file writes) | explode in the build stage and `COPY` the directory to `/app/webapps/ROOT/` (a WAR runs from the archive so the root filesystem can stay read-only) |
| Kubernetes probes | `httpGet` on `:8080/healthz` (`{"status":"UP"}` once every context has started; 503 before). No curl: `HEALTHCHECK` uses `java -cp /opt/tomcat/bin/healthcheck.jar HealthCheck` |
| Logs | stdout only: one-line JUL records plus a JSON access log (one object per request, duration in `elapsedTime` ms, `X-Request-Id` captured). Health probes appear in the access log too; filter `path=/healthz` in the pipeline |
| Shutdown | SIGTERM drains and stops in well under a second when idle; the JVM exits **143**, which is normal. Set `terminationGracePeriodSeconds` above your slowest request |

What the baked configuration changes versus stock Tomcat is documented in the comments of
[images/tomcat/conf/server.xml](images/tomcat/conf/server.xml): no shutdown port, no AJP, no TLS/APR
(terminate TLS at the ingress), no version banner, `RemoteIpValve` for ingress headers, session
persistence off, work directory under `/tmp`. The default heap is 65% of the memory limit (not 75%):
Tomcat's thread stacks, metaspace and direct buffers sit on top of it.

## How it's layered

```
 upstream (pinned by digest in pins.hcl; shown for ONE version, repeated for each)
 ├─ golang:<v>-trixie ───────────► go-build            └─ distroless/static ──► go-runtime
 ├─ temurin:<v>-jdk ┬─ jlink ────► (JRE /opt/jre) ──┐   └─ distroless/base ────► go-runtime-cgo
 │                  └────────────► java-build       └─► distroless/java-base ──► java-runtime
 ├─ python:<v>-trixie + uv ──────► python-build ─ /opt/venv ─┐
 │  python:<v>-slim-trixie ─ harden.sh ──────────────────────┴► python-runtime
 ├─ node:<v>-trixie ─────────────► node-build           └─ distroless/nodejs<v> ──► node-runtime
 └─ tomcat:<t>-jre21 (Tomcat tree) ─┬─ jlink (+rmi, compiler) ──┐
                                    └──────────────────────────┴► distroless/java-base ──► tomcat-runtime

 your app image = <lang>-build:<v> (compile)  ──COPY --from──►  <lang>-runtime:<v> (ship)
```

Versions are a bake **matrix** (`docker-bake.hcl`): adding a version adds a column, not a copy of the Dockerfile.
The same Dockerfile serves every version; the few per-version differences (JDK 17 `jlink` compression,
`jdk.crypto.ec` on ≤ 21, corepack on Node ≥ 25) are handled inside it.

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
| JVM container-aware: `MaxRAMPercentage`, `ExitOnOutOfMemoryError`, tmp dir for `--read-only` | java-runtime / tomcat-runtime `ENV` |
| Tomcat: no shutdown port, no AJP/TLS/APR, no version banner, no stock webapps/scripts, stdout logging, JVM args not logged, `SecurityListener` refuses root | [images/tomcat/](images/tomcat) |
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
* **Pipeline health**: [pipeline-health.yml](.github/workflows/pipeline-health.yml) opens a GitHub issue when a scheduled/`main` run of `build.yml` fails, and a daily [freshness.sh](scripts/freshness.sh) check opens one when any published `:<version>` tag is more than 10 days old (e.g. the workflow was disabled, or GitHub paused the schedule after 60 days of repo inactivity).
* **Add a version** (say Node 28): add `28` to the `versions node` line in [pins.tsv](pins.tsv), `make pins`, `make test ONLY=node:28`. (Tomcat is the same, e.g. add `10.1` to `versions tomcat` and run `make test ONLY=tomcat:10.1-java21`; it multiplies with the Java versions.) Nothing else: the bake matrix, CI matrix targets, verify, smoke and scan scripts all read `pins.tsv`. Tags follow the version (`node-runtime:28`), so teams migrate on their own schedule.
* **Release flow (main)**: `publish` builds each language **once**, pushes only immutable `:<version>-<sha>` candidates, pulls those exact digests back and runs `verify.sh` + `smoke-test.sh` + `scan.sh` on them, signs them, and only then moves the floating `:<version>` tag to the same digest ([promote.sh](scripts/promote.sh)). A failed test or scan leaves the floating tags untouched. PRs and branch dispatches run the same checks on a local build via the `verify` job.
* **Roll back a bad release**: before each publish moves the floating tags, [preserve-previous.sh](scripts/preserve-previous.sh) keeps the digest they currently point at as `:<version>-previous` (same signature, SBOM and provenance). Run the [rollback](.github/workflows/rollback.yml) workflow (`image=node-runtime`, `version=24`) or `REGISTRY=ghcr.io/<owner> scripts/rollback.sh node-runtime 24` to move `:<version>` back. The next weekly publish promotes a fresh digest again, so fix the cause or pause the schedule. Consumers pinning `@sha256:` are unaffected either way.
* **Add a version** (say Node 28): add `28` to the `versions node` line in [pins.tsv](pins.tsv), `make pins`, `make test ONLY=node:28`. Nothing else: the bake matrix, CI matrix targets, verify, smoke and scan scripts all read `pins.tsv`. Tags follow the version (`node-runtime:28`), so teams migrate on their own schedule.
* **Retire a version**: remove it from `pins.tsv` ~6 months before upstream EOL, announce it, and leave the already-published tags in the registry.
* **Docker Hub rate limits**: `make pins` and the first builds pull ~25 upstream images; anonymous pulls are capped (HTTP 429, 100 per hour per IP). Run `docker login` locally. In CI add the optional secrets `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`; the login step is skipped without them.
* **Consumers** should pin `image:tag@sha256:…` and let Renovate/Dependabot bump it; `:<major>` is a convenience tag that moves weekly.
* **Verify a pulled image**: `cosign verify --certificate-identity-regexp 'https://github.com/<org>/<repo>/' --certificate-oidc-issuer https://token.actions.githubusercontent.com <image>@<digest>`
* **Debugging shell-less images**: `kubectl debug -it <pod> --image=busybox --target=<container>` or `docker debug`. Don't add a shell to production images.

## Setup checklist (placeholders to fill in)

1. Check that the `SOURCE_URL` default in [docker-bake.hcl](docker-bake.hcl) and the `ghcr.io/ngpayyappilly/...` defaults in the example Dockerfiles match your real GitHub repo. CI overrides `SOURCE_URL` and `REGISTRY` (`ghcr.io/<owner>`) from the workflow context; for ECR change the login step in `build.yml`.
2. Make the first publish, then pin your app images to the resulting digests.

## Trade-offs and known limitations

* **Python runtime is hardened-slim, not distroless.** `distroless/python3` ships Debian's own Python version and can't take extra system libs. The cost: a `sh` and ~146 MB. If your services are pure-Python wheels and you accept Debian's version, switching is a small change.
* **The JRE is jlinked from Temurin on Ubuntu 24.04 and run on Debian 13 distroless.** glibc is backwards-compatible and this is exercised by `make test`, but it's two distros; if you want one, swap `JAVA_JDK_IMAGE` for a trixie-based JDK. The default module list includes `java.desktop` because Spring/Jackson use `java.beans`; trim it per app with `jdeps`. `jdk.crypto.ec` is added automatically on JDK ≤ 21 (it was merged into `java.base` in 22).
* **`JAVA_TOOL_OPTIONS` prints `Picked up JAVA_TOOL_OPTIONS…` to stderr** on every JVM start (including healthchecks). Harmless; move the flags into your `ENTRYPOINT` if the noise matters.
* **Build images are not gated on CVEs, only reported.** Findings there are in upstream-bundled tooling (e.g. npm/corepack internals) and never ship; runtime images are gated hard.
* **No hardened-OS vendor (Chainguard, Wolfi, Docker Hardened Images).** They give faster CVE turnaround than self-patching Debian, at a licensing/lock-in cost. Worth evaluating once volume justifies it; this repo's `pins.tsv` is the only place you'd change.
* **tomcat-runtime is a shell-less distroless image, and legacy apps lean on things that are not in it.** Likely breakages, in order of how often they bite: (1) **no fonts/fontconfig/libfreetype**: AWT users (JasperReports, POI charts, captchas, image resizing) fail; (2) the JRE is jlinked, so a module outside the list is missing (`java.rmi`, `java.management.rmi`, `java.compiler` are added for Tomcat; check others with `jdeps`); (3) JNI/native libraries have to be copied in by you; (4) anything that shells out (`Runtime.exec`). If you hit (1), (3) or (4) this is the wrong base; a hardened Debian variant using `harden.sh runtime` with `EXTRA_PACKAGES` is the natural next image (same pattern as `python-runtime`). Java 8 -> 17+ also removes JAXB, JAX-WS and `javax.annotation` from the JDK: add them to the WAR.
* **The Tomcat tree is taken from the official `tomcat:<v>-jre21-temurin-noble` image** (pinned by digest, so Apache's checksum/signature verification stays upstream); the JDK in that image is thrown away. One Tomcat pin therefore serves every Java version. A misspelt `-Dtomcat.*` value only logs a WARNING and falls back to Tomcat's default.
* **Only Tomcat 9.0 is built** (the `javax.*` line). 10.1/11 are one `pins.tsv` line away, but the example is JSP-only so it runs unchanged on any of them; a real `jakarta.*` migration is the application's job.
* **Python and Go have no LTS.** Python 3.12 (EOL Oct 2028) through 3.14 are all "supported"; Go supports only the last two releases, so Go versions turn over every ~6 months and `pins.tsv` needs a bump then.
* **Node 26 is brand new LTS** (Oct 2026) and its distroless image is the largest (189 MB); if you want the most battle-tested line today, use 22 or 24.
* **tomcat-runtime** was verified on linux/amd64 for Java 17/21/25 (`verify.sh`, the example under `--read-only --cap-drop ALL`, Trivy gate: 0 findings); the arm64 build of it has not been run.
* **Tested locally (linux/arm64, Docker Desktop):** all 24 images built; `make lint`, `make test` (version + hardening asserts and every example run under `--read-only --cap-drop ALL`) and `make scan` are green. **Not tested:** the multi-arch (QEMU amd64) build, push, SBOM/provenance attestation and cosign signing steps in the GitHub Actions `publish` job have not run yet, so expect small fixes the first time they do.
