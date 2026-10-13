#!/bin/bash
set -euo pipefail

CONFIG="${MATSIM_CONFIG:-/matsim/input/config.xml}"
HEAP_MAX="${MATSIM_HEAP:-8g}"
HEAP_MIN="${MATSIM_HEAP_MIN:-2g}"
EXTRA_JVM="${MATSIM_JVM_OPTS:-}"

echo "[MATSim] Starting: config=${CONFIG}, heap=${HEAP_MIN}/${HEAP_MAX}"
# Class-Path in the jar Manifest expects libs/ next to matsim.jar
cd /matsim
exec java \
    -Xms"${HEAP_MIN}" \
    -Xmx"${HEAP_MAX}" \
    -XX:+UseG1GC \
    -XX:MaxGCPauseMillis=200 \
    ${EXTRA_JVM} \
    -cp "/matsim/matsim.jar:/matsim/libs/*" \
    org.matsim.run.RunMatsim \
    "${CONFIG}" \
    "$@"
