#!/usr/bin/env bash
# Keep what the floating :<version> tags point at as :<version>-previous, the rollback target
# used by scripts/rollback.sh. Run it BEFORE a publish moves the floating tags.
#   REGISTRY=ghcr.io/<owner> scripts/preserve-previous.sh [lang | lang:version]...
# Copies by digest (imagetools create), so no data moves and the old image keeps its signature,
# SBOM and provenance. Images that are not published yet are skipped, and so are tags whose
# :<version>-previous already equals the current digest.
#
# Limitation: when a publish pushes the floating tag directly and then FAILS (e.g. at signing),
# re-running it makes :<version>-previous point at that half-published image. Check what
# :<version>-previous is before relying on it in that situation. (Publishing candidates first
# and moving the floating tag last avoids the problem.)
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

REGISTRY=${REGISTRY:?set REGISTRY, e.g. ghcr.io/<owner>}
run() { if [[ -n "${DRY_RUN:-}" ]]; then echo "+ $*"; else "$@"; fi; }
digest() { docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>/dev/null || true; }

while read -r l v; do
  for r in $(roles "$l"); do
    repo="$REGISTRY/$l-$r"
    cur=$(digest "$repo:$v")
    if [[ "$cur" != sha256:* ]]; then echo "skip     $repo:$v (not published yet)"; continue; fi
    if [[ "$(digest "$repo:$v-previous")" == "$cur" ]]; then echo "unchanged $repo:$v-previous"; continue; fi
    echo "preserve $repo:$v ${cur:0:19}... -> :$v-previous"
    run docker buildx imagetools create --tag "$repo:$v-previous" "$repo@$cur"
  done
done < <(selection "$@")
