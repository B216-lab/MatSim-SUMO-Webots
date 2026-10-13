#!/usr/bin/env bash
# Convert OSM extract → SUMO network for ул. Карла Маркса.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OSM="${STREET_DIR}/osm/karla_marksa.osm"
NET_OUT="${STREET_DIR}/network/karla_marksa.net.xml"
PTLINES_OUT="${STREET_DIR}/demand/ptlines.xml"
PTSTOPS_OUT="${STREET_DIR}/demand/ptstops.xml"

if [[ ! -f "$OSM" ]]; then
  echo "Missing OSM file: $OSM — run fetch_osm.sh first" >&2
  exit 1
fi

mkdir -p "$(dirname "$NET_OUT")" "$(dirname "$PTLINES_OUT")"

echo "netconvert: ${OSM} → ${NET_OUT}"
netconvert \
  --osm-files "$OSM" \
  --output-file "$NET_OUT" \
  --geometry.remove \
  --ramps.guess \
  --junctions.join \
  --tls.guess-signals \
  --tls.discard-simple \
  --tls.join \
  --edges.join \
  --remove-edges.isolated \
  --keep-edges.by-vclass passenger,bus,tram,pedestrian,bicycle \
  --ptstop-output "$PTSTOPS_OUT" \
  --ptline-output "$PTLINES_OUT" \
  --output.street-names true \
  --type-files "${SUMO_HOME:-/usr/share/sumo}/data/typemap/osmNetconvert.typ.xml" \
  --proj.utm \
  --verbose false

echo "OK: network=${NET_OUT}"
echo "OK: ptstops=${PTSTOPS_OUT}"
echo "OK: ptlines=${PTLINES_OUT}"
