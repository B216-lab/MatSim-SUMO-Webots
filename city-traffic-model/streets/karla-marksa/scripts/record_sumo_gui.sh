#!/usr/bin/env bash
# Record a headless SUMO-GUI clip (Xvfb + ffmpeg x11grab) using MATSim routes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG="${STREET_DIR}/config/simulation.sumocfg"
GUI_SETTINGS="${STREET_DIR}/config/gui-settings.xml"
SECONDS_REC=300
OUTPUT=""
SCREEN_RES="${SCREEN_RES:-1280x720x24}"
DISPLAY_NUM=99

usage() {
  cat <<EOF
Usage: $0 [--config PATH] [--gui-settings PATH] [--seconds N] --output PATH.mp4
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --gui-settings) GUI_SETTINGS="$2"; shift 2 ;;
    --seconds) SECONDS_REC="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$OUTPUT" ]] || { echo "--output is required" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 1; }
[[ -f "$GUI_SETTINGS" ]] || { echo "GUI settings not found: $GUI_SETTINGS" >&2; exit 1; }
command -v sumo-gui >/dev/null || { echo "sumo-gui not found" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found (rebuild traffic-sim/sumo with ffmpeg)" >&2; exit 1; }
command -v Xvfb >/dev/null || { echo "Xvfb not found" >&2; exit 1; }

# sumocfg paths are relative to the street directory.
cd "$STREET_DIR"
# Resolve config/gui paths after cd if they were relative.
[[ "${CONFIG}" = /* ]] || CONFIG="${STREET_DIR}/${CONFIG}"
[[ "${GUI_SETTINGS}" = /* ]] || GUI_SETTINGS="${STREET_DIR}/${GUI_SETTINGS}"
[[ "${OUTPUT}" = /* ]] || OUTPUT="${STREET_DIR}/${OUTPUT}"
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
GUI_SETTINGS="$(cd "$(dirname "$GUI_SETTINGS")" && pwd)/$(basename "$GUI_SETTINGS")"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT")" && pwd)"
OUTPUT="${OUTPUT_DIR}/$(basename "$OUTPUT")"


VIDEO_SIZE="$(echo "${SCREEN_RES}" | awk -F'x' '{print $1 "x" $2}')"
if [[ ! "${VIDEO_SIZE}" =~ ^[0-9]+x[0-9]+$ ]]; then
  VIDEO_SIZE="1280x720"
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true

echo "[SUMO-record] Xvfb :${DISPLAY_NUM} (${SCREEN_RES}), ${SECONDS_REC}s → ${OUTPUT}"
Xvfb ":${DISPLAY_NUM}" -screen 0 "${SCREEN_RES}" +extension GLX +render -noreset &
XVFB_PID=$!
for _ in $(seq 1 20); do
  [[ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]] && break
  sleep 0.5
done
export DISPLAY=":${DISPLAY_NUM}"

# Optional WM so sumo-gui gets a normal window; ignore failure.
fluxbox >/tmp/fluxbox-record.log 2>&1 &
FLUX_PID=$!
sleep 1

ffmpeg -y -nostdin \
  -f x11grab -video_size "${VIDEO_SIZE}" -framerate 10 -i ":${DISPLAY_NUM}.0" \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 23 \
  "${OUTPUT}" >/tmp/ffmpeg-sumo-record.log 2>&1 &
FFMPEG_PID=$!
sleep 1

cleanup() {
  if [[ -n "${SUMO_PID:-}" ]] && kill -0 "${SUMO_PID}" 2>/dev/null; then
    kill -TERM "${SUMO_PID}" 2>/dev/null || true
    wait "${SUMO_PID}" 2>/dev/null || true
  fi
  if [[ -n "${FFMPEG_PID:-}" ]] && kill -0 "${FFMPEG_PID}" 2>/dev/null; then
    kill -INT "${FFMPEG_PID}" 2>/dev/null || true
    wait "${FFMPEG_PID}" 2>/dev/null || true
  fi
  if [[ -n "${FLUX_PID:-}" ]] && kill -0 "${FLUX_PID}" 2>/dev/null; then
    kill -TERM "${FLUX_PID}" 2>/dev/null || true
  fi
  if [[ -n "${XVFB_PID:-}" ]] && kill -0 "${XVFB_PID}" 2>/dev/null; then
    kill -TERM "${XVFB_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --quit-on-end closes when simulation reaches --end; --start auto-runs.
# Wall-clock recording window is SECONDS_REC; sim end matches so the clip ends with the run.
sumo-gui \
  --configuration-file "${CONFIG}" \
  --gui-settings-file "${GUI_SETTINGS}" \
  --start \
  --quit-on-end \
  --end "${SECONDS_REC}" \
  --no-step-log \
  --xml-validation never \
  --window-size "${VIDEO_SIZE/x/,}" \
  >/tmp/sumo-gui-record.log 2>&1 &
SUMO_PID=$!

# Prefer waiting for sumo-gui to exit; also cap wall time (gui can be slower than realtime).
WALL_LIMIT=$((SECONDS_REC * 3 + 60))
elapsed=0
while kill -0 "${SUMO_PID}" 2>/dev/null; do
  sleep 1
  elapsed=$((elapsed + 1))
  if [[ "${elapsed}" -ge "${WALL_LIMIT}" ]]; then
    echo "[SUMO-record] Wall-time limit reached (${WALL_LIMIT}s), stopping sumo-gui"
    break
  fi
done

cleanup
trap - EXIT

if [[ ! -f "${OUTPUT}" ]]; then
  echo "[SUMO-record] ERROR: missing ${OUTPUT}" >&2
  echo "[SUMO-record] sumo-gui log:" >&2
  cat /tmp/sumo-gui-record.log >&2 || true
  echo "[SUMO-record] ffmpeg log:" >&2
  cat /tmp/ffmpeg-sumo-record.log >&2 || true
  exit 1
fi

SIZE="$(wc -c < "${OUTPUT}" | tr -d ' ')"
if [[ "${SIZE}" -lt 1024 ]]; then
  echo "[SUMO-record] ERROR: file too small (${SIZE} bytes): ${OUTPUT}" >&2
  cat /tmp/sumo-gui-record.log >&2 || true
  cat /tmp/ffmpeg-sumo-record.log >&2 || true
  exit 1
fi

echo "[SUMO-record] Done: ${OUTPUT} (${SIZE} bytes)"
