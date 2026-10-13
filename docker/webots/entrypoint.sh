#!/bin/bash
set -euo pipefail

# In-container listen ports (Docker publishes host ports onto these).
STREAM_PORT=1234
VIEWER_PORT="${WEBOTS_VIEWER_PORT:-8080}"
# Host-side ports for browser URL hints (must match docker -p / compose ports:).
STREAM_HOST_PORT="${STREAM_HOST_PORT:-$STREAM_PORT}"
VIEWER_HOST_PORT="${VIEWER_HOST_PORT:-$VIEWER_PORT}"
WORLD="${WEBOTS_WORLD:-/worlds/default.wbt}"
NOVNC="${NOVNC_ENABLED:-false}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
SCREEN_RES="${SCREEN_RES:-1920x1080x24}"
DISPLAY_NUM=99
RECORD_MP4="${WEBOTS_RECORD_MP4:-}"
RECORD_SECONDS="${WEBOTS_RECORD_SECONDS:-60}"

# Parse SCREEN_RES (e.g. 1280x720x24) into WIDTHxHEIGHT for ffmpeg.
VIDEO_SIZE="$(echo "${SCREEN_RES}" | awk -F'x' '{print $1 "x" $2}')"
if [[ ! "${VIDEO_SIZE}" =~ ^[0-9]+x[0-9]+$ ]]; then
  VIDEO_SIZE="1280x720"
fi

# 1. Очистка остаточных lock-файлов от предыдущего запуска (при рестарте контейнера)
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true

# 2. Запуск виртуального дисплея
echo "[WeBots] Starting Xvfb on display :${DISPLAY_NUM} (${SCREEN_RES})"
Xvfb ":${DISPLAY_NUM}" -screen 0 "${SCREEN_RES}" +extension GLX +render -noreset &
XVFB_PID=$!

# Ждём Xvfb (до 10 секунд)
for i in $(seq 1 20); do
    [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break
    sleep 0.5
done
export DISPLAY=":${DISPLAY_NUM}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"

# 3. Опциональный noVNC (для доступа к GUI через браузер)
if [ "${NOVNC}" = "true" ]; then
    echo "[WeBots] Starting noVNC on port ${NOVNC_PORT}"
    x11vnc -display ":${DISPLAY_NUM}" -nopw -listen 0.0.0.0 -rfbport "${VNC_PORT}" -forever -shared &
    websockify --web=/usr/share/novnc "${NOVNC_PORT}" "localhost:${VNC_PORT}" &
fi

# 4. Запуск WeBots в headless-режиме с web streaming
echo "[WeBots] Starting simulation: ${WORLD}"
echo "[WeBots] Streaming available at http://<host>:${STREAM_HOST_PORT}"

if [ ! -f "${WORLD}" ]; then
    echo "[WeBots] World file not found: ${WORLD}, copying bundled default"
    cp /opt/webots-defaults/default.wbt /worlds/default.wbt
    WORLD=/worlds/default.wbt
fi

# 5. Раздаём встроенный WeBots streaming viewer через HTTP (stream mode only)
VIEWER_DIR="/usr/local/webots/resources/web/streaming_viewer"

cleanup_recording() {
    local webots_pid="${1:-}"
    local ffmpeg_pid="${2:-}"
    if [[ -n "${webots_pid}" ]] && kill -0 "${webots_pid}" 2>/dev/null; then
        echo "[WeBots] Stopping Webots (pid ${webots_pid})"
        kill -TERM "${webots_pid}" 2>/dev/null || true
        wait "${webots_pid}" 2>/dev/null || true
    fi
    if [[ -n "${ffmpeg_pid}" ]] && kill -0 "${ffmpeg_pid}" 2>/dev/null; then
        echo "[WeBots] Stopping ffmpeg (pid ${ffmpeg_pid})"
        kill -INT "${ffmpeg_pid}" 2>/dev/null || true
        wait "${ffmpeg_pid}" 2>/dev/null || true
    fi
}

if [[ -n "${RECORD_MP4}" ]]; then
    RECORD_DIR="$(dirname "${RECORD_MP4}")"
    mkdir -p "${RECORD_DIR}"

    echo "[WeBots] Recording ${RECORD_SECONDS}s to ${RECORD_MP4} (${VIDEO_SIZE} @ 25fps)"
    # Give Xvfb / GL a moment before grabbing frames.
    sleep 1

    ffmpeg -y -nostdin \
        -f x11grab -video_size "${VIDEO_SIZE}" -framerate 25 -i ":${DISPLAY_NUM}.0" \
        -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 23 \
        "${RECORD_MP4}" >/tmp/ffmpeg-record.log 2>&1 &
    FFMPEG_PID=$!

    # Brief delay so ffmpeg attaches before the first frames render.
    sleep 1

    # Fullscreen so x11grab captures the 3D view (windowed WeBots is a small corner of Xvfb).
    # Do not --minimize while recording.
    webots \
        --stdout \
        --stderr \
        --batch \
        --mode=realtime \
        --fullscreen \
        "${WORLD}" &
    WEBOTS_PID=$!

    trap 'cleanup_recording "${WEBOTS_PID:-}" "${FFMPEG_PID:-}"' EXIT

    # Wait for the recording window, then stop both processes.
    sleep "${RECORD_SECONDS}"
    cleanup_recording "${WEBOTS_PID}" "${FFMPEG_PID}"
    trap - EXIT

    if [[ ! -f "${RECORD_MP4}" ]]; then
        echo "[WeBots] ERROR: recorded file missing: ${RECORD_MP4}" >&2
        echo "[WeBots] ffmpeg log:" >&2
        cat /tmp/ffmpeg-record.log >&2 || true
        exit 1
    fi

    SIZE="$(wc -c < "${RECORD_MP4}" | tr -d ' ')"
    if [[ "${SIZE}" -lt 1024 ]]; then
        echo "[WeBots] ERROR: recorded file too small (${SIZE} bytes): ${RECORD_MP4}" >&2
        echo "[WeBots] ffmpeg log:" >&2
        cat /tmp/ffmpeg-record.log >&2 || true
        exit 1
    fi

    echo "[WeBots] Recording complete: ${RECORD_MP4} (${SIZE} bytes)"
    exit 0
fi

# Interactive / stream mode (default): long-running.
# Viewer page is served inside the container on VIEWER_PORT; browser must use host ports.
echo "[WeBots] Viewer available at http://<host>:${VIEWER_HOST_PORT}/?host=<host>&port=${STREAM_HOST_PORT}"
python3 -m http.server "${VIEWER_PORT}" --directory "${VIEWER_DIR}" &

# R2023b: --stream is a boolean flag; port is always 1234 inside container.
# Host-side port differentiation is handled by Docker port mapping + STREAM_HOST_PORT hint.
exec webots \
    --batch \
    --mode=realtime \
    --minimize \
    --stream \
    "${WORLD}"
