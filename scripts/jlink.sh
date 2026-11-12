#!/bin/sh
# Build the trimmed JRE at /opt/jre. Shared by images/java and images/tomcat so the per-LTS
# rules below live in exactly one place.  Run inside a JDK image (JAVA_HOME set).
#
# Env:  JAVA_VERSION         required, e.g. 21
#       JLINK_MODULES        override the default module list entirely (optional)
#       JLINK_EXTRA_MODULES  comma separated modules appended to the list (optional)
set -eux

: "${JAVA_VERSION:?JAVA_VERSION must be set}"

# java.desktop is here because Spring/Jackson/etc. use java.beans. Drop it if you
# know you don't. Add jdk.localedata for non-English locales.
# Per-app minimum:  jdeps --print-module-deps --ignore-missing-deps app.jar
default_modules="java.base,java.logging,java.xml,java.naming,java.sql,java.management,java.net.http,java.security.jgss,java.security.sasl,java.instrument,java.prefs,java.transaction.xa,java.desktop,jdk.unsupported,jdk.zipfs,jdk.httpserver,jdk.management,jdk.management.agent,jdk.jfr,jdk.naming.dns,jdk.crypto.cryptoki,jdk.charsets"
modules=${JLINK_MODULES:-$default_modules}
if [ -n "${JLINK_EXTRA_MODULES:-}" ]; then modules="${modules},${JLINK_EXTRA_MODULES}"; fi

# Per-LTS differences:
#   17      --compress=2 (the zip-N spelling arrived in 21); jdk.crypto.ec is a separate module
#   21      zip-6; jdk.crypto.ec is still a separate module (merged into java.base in 22)
#   25+     zip-6; nothing extra
case "${JAVA_VERSION}" in
  17) compress=2;     modules="${modules},jdk.crypto.ec" ;;
  21) compress=zip-6; modules="${modules},jdk.crypto.ec" ;;
  *)  compress=zip-6 ;;
esac

jlink \
  --add-modules "${modules}" \
  --strip-debug --no-header-files --no-man-pages \
  --compress="${compress}" \
  --generate-cds-archive \
  --output /opt/jre

# Temurin-on-Ubuntu symlinks cacerts into /etc/ssl; materialise the real file
# so the trust store travels with the JRE into the distroless image.
cp --dereference --remove-destination \
   "$JAVA_HOME/lib/security/cacerts" /opt/jre/lib/security/cacerts
/opt/jre/bin/java -version
