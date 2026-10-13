#!/bin/bash
set -euo pipefail

# Режимы запуска SUMO-контейнера:
#   traci-server  — headless TraCI-сервер для Python-агентов (по умолчанию)
#   gui           — sumo-gui с Xvfb + fluxbox + noVNC (браузерный доступ)
#   netedit       — netedit с Xvfb + fluxbox + noVNC (редактирование сети)
#   batch         — разовый прогон и выход

MODE="${SUMO_MODE:-traci-server}"
CONFIG="${SUMO_CONFIG:-/scenarios/default.sumocfg}"
TRACI_PORT="${TRACI_PORT:-8813}"
NOVNC_PORT="${SUMO_NOVNC_PORT:-6080}"
VNC_PORT="${SUMO_VNC_PORT:-5900}"
SCREEN_RES="${SCREEN_RES:-1280x800x24}"
DISPLAY_NUM=99

# Если конфиг не найден — копируем встроенный дефолтный сценарий
if [ ! -f "${CONFIG}" ]; then
    echo "[SUMO] Config not found at ${CONFIG}, copying bundled default scenario"
    cp /opt/sumo-defaults/default.sumocfg /scenarios/default.sumocfg
    cp /opt/sumo-defaults/default.net.xml  /scenarios/default.net.xml
fi

start_display() {
    rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true
    export DISPLAY=":${DISPLAY_NUM}"
    echo "[SUMO] Starting Xvfb on display :${DISPLAY_NUM} (${SCREEN_RES})"
    Xvfb ":${DISPLAY_NUM}" -screen 0 "${SCREEN_RES}" +extension GLX +render -noreset &
    for i in $(seq 1 20); do
        [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break
        sleep 0.5
    done
    # Window manager: fluxbox provides title bars and resize handles.
    # fluxbox is started before the GUI app and given 1s to fully initialize.
    fluxbox &
    sleep 1
    echo "[SUMO] Starting noVNC on port ${NOVNC_PORT}"
    x11vnc -display ":${DISPLAY_NUM}" -nopw -listen 0.0.0.0 -rfbport "${VNC_PORT}" -forever -shared -quiet &
    websockify --web=/usr/share/novnc "${NOVNC_PORT}" "localhost:${VNC_PORT}" &
    echo "[SUMO] GUI available at http://<host>:${NOVNC_PORT}/vnc.html"
}

case "$MODE" in
  traci-server)
    echo "[SUMO] Starting TraCI server on port ${TRACI_PORT}, config: ${CONFIG}"
    exec sumo \
      --remote-port "${TRACI_PORT}" \
      --configuration-file "${CONFIG}" \
      --no-step-log \
      --xml-validation never \
      --no-warnings
    ;;
  gui)
    start_display
    echo "[SUMO] Starting sumo-gui, config: ${CONFIG}"
    exec sumo-gui \
      --configuration-file "${CONFIG}" \
      --remote-port "${TRACI_PORT}" \
      --xml-validation never
    ;;
  netedit)
    start_display
    NET="${SUMO_NET:-/scenarios/default.net.xml}"
    echo "[SUMO] Starting netedit, network: ${NET}"
    exec netedit "${NET}"
    ;;
  batch)
    echo "[SUMO] Batch run: ${CONFIG}"
    exec sumo --configuration-file "${CONFIG}"
    ;;
  *)
    exec "$@"
    ;;
esac
