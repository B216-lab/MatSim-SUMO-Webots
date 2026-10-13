#!/usr/bin/env bash
# Launch WeBots project for ул. Карла Маркса (SumoInterface via sumo_supervisor).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJ="${STREET_DIR}/webots_project"
VIEWER_PORT="${WEBOTS_VIEWER_PORT:-18081}"
STREAM_HOST_PORT="${WEBOTS_STREAM_HOST_PORT:-1240}"

"$SCRIPT_DIR/sync_webots_net.sh"

# Sync world + SUMO net into Webots project layout
mkdir -p "${PROJ}/worlds" "${PROJ}/controllers"
cp -f "${STREET_DIR}/worlds/karla_marksa.wbt" "${PROJ}/worlds/"
rm -rf "${PROJ}/worlds/karla_marksa_net"
cp -a "${STREET_DIR}/worlds/karla_marksa_net" "${PROJ}/worlds/"

# Ensure sumo_supervisor controller exists in the project
if [[ ! -f "${PROJ}/controllers/sumo_supervisor/sumo_supervisor.py" ]]; then
  docker run --rm --entrypoint bash traffic-sim/webots:R2023b \
    -c 'tar -C /usr/local/webots/projects/default/controllers -cf - sumo_supervisor' \
    | tar -C "${PROJ}/controllers" -xf -
fi

echo "Starting WeBots project ${PROJ}"
echo "  stream: http://<host>:${STREAM_HOST_PORT}"
echo "  viewer: http://<host>:${VIEWER_PORT}/?host=<host>&port=${STREAM_HOST_PORT}"
exec docker run --rm \
  -v "${PROJ}:/project" \
  -e WEBOTS_WORLD=/project/worlds/karla_marksa.wbt \
  -e SUMO_HOME=/usr/share/sumo \
  -e WEBOTS_VIEWER_PORT="${VIEWER_PORT}" \
  -e VIEWER_HOST_PORT="${VIEWER_PORT}" \
  -e STREAM_HOST_PORT="${STREAM_HOST_PORT}" \
  -e SCREEN_RES="${SCREEN_RES:-1280x720x24}" \
  -p "${VIEWER_PORT}:${VIEWER_PORT}" \
  -p "${STREAM_HOST_PORT}:1234" \
  traffic-sim/webots:R2023b
