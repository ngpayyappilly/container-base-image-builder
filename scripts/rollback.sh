#!/usr/bin/env bash
# Roll a floating tag back to the digest it pointed at before the last promotion.
#   REGISTRY=ghcr.io/<owner> scripts/rollback.sh <image> <version>      e.g. node-runtime 24
# Moves :<version> to whatever :<version>-previous points at. No rebuild; the old digest is
# still signed and still has its SBOM/provenance. :<version>-previous is left as is.
# NOTE: the next successful weekly publish promotes a new digest again, so pair a rollback
# with a fix (or disable the schedule) if the regression is in the pipeline itself.
set -euo pipefail
REGISTRY=${REGISTRY:?set REGISTRY, e.g. ghcr.io/<owner>}
image=${1:?usage: rollback.sh <image> <version>}
v=${2:?usage: rollback.sh <image> <version>}
# these come from workflow inputs: accept only plain image names and versions
[[ "$image" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && "$v" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "bad image/version" >&2; exit 2; }
run() { if [[ -n "${DRY_RUN:-}" ]]; then echo "+ $*"; else "$@"; fi; }

repo="$REGISTRY/$image"
prev=$(docker buildx imagetools inspect "$repo:$v-previous" --format '{{.Manifest.Digest}}' 2>/dev/null || true)
[[ "$prev" == sha256:* ]] || { echo "no $repo:$v-previous to roll back to" >&2; exit 1; }
cur=$(docker buildx imagetools inspect "$repo:$v" --format '{{.Manifest.Digest}}' 2>/dev/null || true)
echo "rollback $repo:$v  $cur -> $prev"
run docker buildx imagetools create --tag "$repo:$v" "$repo@$prev"
