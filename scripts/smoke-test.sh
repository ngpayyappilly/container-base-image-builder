#!/usr/bin/env bash
# Build every example app on the *locally built* base images, once per supported version,
# then run it with the strictest runtime flags we recommend and check it still works:
#   read-only rootfs, all capabilities dropped, no-new-privileges, memory/pids limits.
# Usage: REGISTRY=local scripts/smoke-test.sh [lang | lang:version]...   (default: everything)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

REGISTRY=${REGISTRY:-local}

# command used by HEALTHCHECK in each example (run via `docker exec` to prove it works)
health_cmd() {
  case $1 in
    go)     echo "/app healthcheck" ;;
    java)   echo "java -jar /app/app.jar healthcheck" ;;
    python) echo "python app/main.py healthcheck" ;;
    node)   echo "/nodejs/bin/node server.js healthcheck" ;;
  esac
}

cid=""
cleanup() { if [[ -n "$cid" ]]; then docker rm -f "$cid" >/dev/null 2>&1 || true; fi; }
trap cleanup EXIT

while read -r l v; do
  echo "== example/$l on $REGISTRY/$l-build:$v -> $REGISTRY/$l-runtime:$v"
  img="example-$l-$(slug "$v"):smoke"
  docker build -q -t "$img" \
    --build-arg "BUILD_IMAGE=$REGISTRY/$l-build:$v" \
    --build-arg "RUNTIME_IMAGE=$REGISTRY/$l-runtime:$v" \
    "examples/$l" >/dev/null

  cid=$(docker run -d --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
        --pids-limit 200 --memory 256m -p 127.0.0.1::8080 "$img")
  port=$(docker port "$cid" 8080/tcp | head -1 | sed 's/.*://')

  body=""
  for _ in $(seq 1 40); do
    body=$(curl -fsS --max-time 2 "http://127.0.0.1:$port/" 2>/dev/null) && break || sleep 0.5
  done
  [[ -n "$body" ]] || { echo "  FAIL: no response"; docker logs "$cid"; exit 1; }
  echo "  GET /        -> $body"
  [[ "$body" == *65532* || "$body" == *nonroot* ]] || { echo "  FAIL: not running as 65532"; exit 1; }
  [[ "$(curl -fsS "http://127.0.0.1:$port/healthz")" == ok ]] || { echo "  FAIL: /healthz"; exit 1; }
  # shellcheck disable=SC2046  # intentional word splitting of the command
  docker exec "$cid" $(health_cmd "$l") 2>/dev/null && echo "  HEALTHCHECK command -> exit 0"
  echo "  image size: $(docker image inspect -f '{{.Size}}' "$img" | awk '{printf "%.0f MB", $1/1e6}')"
  cleanup; cid=""
done < <(selection "$@")
echo "SMOKE TESTS PASSED"
