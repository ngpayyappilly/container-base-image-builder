#!/usr/bin/env bash
# Vulnerability gate.
#   *-runtime images : MUST have zero fixable HIGH/CRITICAL findings (exit 1 otherwise)
#   *-build images   : reported only. They never ship to production, and most findings
#                      are inside upstream-bundled tooling (npm/corepack internals, etc.).
# Usage: REGISTRY=local scripts/scan.sh [lang | lang:version]...   (default: everything)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

REGISTRY=${REGISTRY:-local}
opts=(--quiet --ignore-unfixed --severity "HIGH,CRITICAL")

sel=$(selection "$@")
while read -r l v; do
  for r in $(roles "$l"); do
    [[ "$r" == runtime* ]] || continue
    echo "== $REGISTRY/$l-$r:$v (gate)"
    trivy image "${opts[@]}" --exit-code 1 "$REGISTRY/$l-$r:$v"
  done
done <<<"$sel"
while read -r l v; do
  echo "== $REGISTRY/$l-build:$v (report only)"
  trivy image "${opts[@]}" "$REGISTRY/$l-build:$v" || true
done <<<"$sel"
echo "SCAN GATE PASSED"
