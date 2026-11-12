#!/usr/bin/env bash
# Daily gate on what consumers can pull RIGHT NOW. scan.sh gates a build before it ships;
# this catches CVEs disclosed after it shipped (the weekly rebuild can be 6 days away).
#   *-runtime images : any fixable HIGH/CRITICAL -> listed, exit 1
#   *-build images   : not scanned (never ship; reported by scan.sh at build time)
# Unlike scan.sh it scans EVERYTHING before failing, so one issue lists all offenders.
# Usage: REGISTRY=ghcr.io/<owner> scripts/scan-published.sh [lang | lang:version]...
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
. scripts/lib.sh

REGISTRY=${REGISTRY:?set REGISTRY, e.g. ghcr.io/<owner>}
report=${REPORT_FILE:-scan-published.txt}
: >"$report"
bad=0

while read -r l v; do
  for r in $(roles "$l"); do
    [[ "$r" == runtime* ]] || continue
    ref="$REGISTRY/$l-$r:$v"
    echo "== $ref"
    out=$(mktemp)
    # Any non-zero exit is a failure: findings AND scanner errors (image missing, registry
    # down; trivy also exits 1 for those). Failing closed is deliberate - an unscannable
    # published image must never read as "clean". The report holds trivy's output to tell them apart.
    rc=0
    trivy image --quiet --ignore-unfixed --severity HIGH,CRITICAL --exit-code 1 "$ref" >"$out" 2>&1 || rc=$?
    if (( rc != 0 )); then
      bad=1
      { echo "### $ref (trivy exit $rc)"; cat "$out"; echo; } >>"$report"
      echo "  FINDINGS / SCAN ERROR (exit $rc)"
    else
      echo "  clean"
    fi
    rm -f "$out"
  done
done < <(selection "$@")

if (( bad )); then echo "PUBLISHED IMAGES HAVE FIXABLE HIGH/CRITICAL FINDINGS (see $report)"; exit 1; fi
echo "PUBLISHED IMAGES CLEAN"
