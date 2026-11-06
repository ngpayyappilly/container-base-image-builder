# shellcheck shell=bash
# Shared helpers, sourced by verify.sh / smoke-test.sh / scan.sh / targets.sh.
# Reads the supported versions from pins.tsv (the single source of truth).
# bash 3.2 compatible (macOS default shell): no associative arrays, no mapfile.

ALL_LANGS="go java python node"

# versions <lang>  -> one version per line
versions() { awk -F'\t' -v l="$1" '$1=="versions" && $2==l {for (i = 3; i <= NF; i++) print $i}' pins.tsv; }

# roles <lang>  -> image roles published for that language
roles() { case $1 in go) echo "build runtime runtime-cgo" ;; *) echo "build runtime" ;; esac; }

# slug 1.26 -> 1-26   (bake target names cannot contain dots)
slug() { echo "${1//./-}"; }

# selection [lang | lang:version]...  -> "lang version" lines; no args = everything
selection() {
  local s l v
  if [ $# -eq 0 ]; then set -- $ALL_LANGS; fi
  for s in "$@"; do
    l=${s%%:*}; v=""
    case $s in *:*) v=${s#*:} ;; esac
    if [ -n "$v" ]; then
      versions "$l" | grep -qx "$v" || { echo "unknown selector '$s' (see pins.tsv)" >&2; return 1; }
      echo "$l $v"
    else
      [ -n "$(versions "$l")" ] || { echo "unknown language '$l'" >&2; return 1; }
      for v in $(versions "$l"); do echo "$l $v"; done
    fi
  done
}
