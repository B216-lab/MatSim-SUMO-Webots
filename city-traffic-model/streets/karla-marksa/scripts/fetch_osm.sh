#!/usr/bin/env bash
# Fetch OSM extract for ул. Карла Маркса, Irkutsk via Overpass API.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${STREET_DIR}/osm/karla_marksa.osm"

# lon_min, lat_min, lon_max, lat_max
BBOX="${BBOX:-104.278,52.278,104.312,52.291}"
IFS=',' read -r LON_MIN LAT_MIN LON_MAX LAT_MAX <<< "$BBOX"

OVERPASS_URL="${OVERPASS_URL:-https://overpass-api.de/api/interpreter}"

QUERY=$(cat <<EOF
[out:xml][timeout:180];
(
  way["highway"](${LAT_MIN},${LON_MIN},${LAT_MAX},${LON_MAX});
  way["railway"="tram"](${LAT_MIN},${LON_MIN},${LAT_MAX},${LON_MAX});
  node["highway"="traffic_signals"](${LAT_MIN},${LON_MIN},${LAT_MAX},${LON_MAX});
  node["highway"="crossing"](${LAT_MIN},${LON_MIN},${LAT_MAX},${LON_MAX});
  node["railway"="tram_stop"](${LAT_MIN},${LON_MIN},${LAT_MAX},${LON_MAX});
  node["public_transport"="platform"](${LAT_MIN},${LON_MIN},${LAT_MAX},${LON_MAX});
  node["amenity"="bus_stop"](${LAT_MIN},${LON_MIN},${LAT_MAX},${LON_MAX});
  way["building"](${LAT_MIN},${LON_MIN},${LAT_MAX},${LON_MAX});
);
(._;>;);
out body;
EOF
)

mkdir -p "$(dirname "$OUT")"
echo "Fetching OSM bbox=${BBOX} → ${OUT}"
curl -fsSL --retry 3 --retry-delay 5 \
  -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "data=${QUERY}" \
  "$OVERPASS_URL" \
  -o "$OUT"

# Basic sanity: must contain at least one highway way
if ! grep -q 'k="highway"' "$OUT"; then
  echo "ERROR: OSM extract has no highway ways" >&2
  exit 1
fi

BYTES=$(wc -c < "$OUT")
echo "OK: wrote ${OUT} (${BYTES} bytes)"
