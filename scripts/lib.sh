# shellcheck shell=bash
# Shared helpers, sourced by verify.sh / smoke-test.sh / scan.sh / targets.sh.
# Reads the supported versions from pins.tsv (the single source of truth).
# bash 3.2 compatible (macOS default shell): no associative arrays, no mapfile.

ALL_LANGS="go java python node tomcat"

# pin_versions <lang>  -> the raw `versions <lang>` line from pins.tsv, one per line
pin_versions() { awk -F'\t' -v l="$1" '$1=="versions" && $2==l {for (i = 3; i <= NF; i++) print $i}' pins.tsv; }

# versions <lang>  -> one published version (= image tag) per line.
# tomcat is two-axis (tomcat x java) and tagged <tomcat>-java<java>, e.g. 9.0-java21.
versions() {
  local t j
  if [ "$1" = tomcat ]; then
    for t in $(pin_versions tomcat); do for j in $(pin_versions java); do echo "$t-java$j"; done; done
  else
    pin_versions "$1"
  fi
}

# roles <lang>  -> image roles published for that language
roles() { case $1 in go) echo "build runtime runtime-cgo" ;; tomcat) echo "runtime" ;; *) echo "build runtime" ;; esac; }

# build_image <lang> <version> -> the toolchain image examples build with (tomcat reuses java-build)
build_image() { case $1 in tomcat) echo "java-build:${2##*-java}" ;; *) echo "$1-build:$2" ;; esac; }

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
