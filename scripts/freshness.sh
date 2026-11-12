#!/usr/bin/env bash
# Freshness check on the PUBLISHED floating tags: the weekly rebuild is what delivers OS
# security patches, so a tag whose org.opencontainers.image.created is older than
# MAX_AGE_DAYS means the pipeline has silently stopped publishing.
# Usage: REGISTRY=ghcr.io/<owner> [MAX_AGE_DAYS=10] scripts/freshness.sh [lang | lang:version]...
# Exit 1 (and list every offender) if any image is stale or unreadable.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

REGISTRY=${REGISTRY:?set REGISTRY, e.g. ghcr.io/<owner>}
MAX_AGE_DAYS=${MAX_AGE_DAYS:-10}
now=$(date -u +%s)
stale=0

while read -r l v; do
  for r in $(roles "$l"); do
    ref="$REGISTRY/$l-$r:$v"
    # .Image is the image config (a map of platform -> config for multi-arch); search it for
    # the label instead of depending on the exact shape.
    created=$(docker buildx imagetools inspect "$ref" --format '{{json .Image}}' 2>/dev/null |
      jq -r '[.. | objects | select(has("org.opencontainers.image.created")) | .["org.opencontainers.image.created"]] | first // empty' || true)
    if [[ -z "$created" ]]; then
      echo "STALE?  $ref: cannot read image.created (missing image or label)"; stale=1; continue
    fi
    age=$(( (now - $(date -u -d "$created" +%s)) / 86400 ))
    if (( age > MAX_AGE_DAYS )); then
      echo "STALE   $ref: built $created (${age}d old, limit ${MAX_AGE_DAYS}d)"; stale=1
    else
      echo "fresh   $ref: ${age}d"
    fi
  done
done < <(selection "$@")

if (( stale )); then echo "FRESHNESS CHECK FAILED"; exit 1; fi
echo "ALL IMAGES FRESH"
