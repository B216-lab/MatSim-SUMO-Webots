#!/usr/bin/env bash
# Export MATSim output_plans → SUMO route files used by city + street simulations.
# Requires a completed MATSim run (output_plans.xml.gz).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLANS="${1:-$ROOT/base/matsim/output/output_plans.xml.gz}"
SUMO_NET="${SUMO_NET:-$ROOT/streets/karla-marksa/network/karla_marksa.net.xml}"
CITY_OUT="${CITY_OUT:-$ROOT/base/demand/irkutsk.rou.xml}"
STREET_OUT="${STREET_OUT:-$ROOT/streets/karla-marksa/demand/street_matsim.rou.xml}"
CORRIDOR_NAME="${CORRIDOR_NAME:-Маркса}"
STREET_WINDOW="${STREET_WINDOW:-3600}"
CITY_WINDOW="${CITY_WINDOW:-86400}"

if [[ ! -f "$PLANS" ]]; then
  echo "MATSim plans not found: $PLANS" >&2
  echo "Run MATSim first (see prepare_matsim.sh / README phase 2)." >&2
  exit 1
fi
if [[ ! -f "$SUMO_NET" ]]; then
  echo "SUMO net not found: $SUMO_NET" >&2
  exit 1
fi

CONVERT="$ROOT/base/scripts/matsim_plans_to_sumo.py"

echo "==> Full-network SUMO demand → $CITY_OUT"
python3 "$CONVERT" \
  --plans "$PLANS" \
  --out "$CITY_OUT" \
  --window "$CITY_WINDOW"

echo "==> Corridor-filtered street demand → $STREET_OUT"
python3 "$CONVERT" \
  --plans "$PLANS" \
  --out "$STREET_OUT" \
  --sumo-net "$SUMO_NET" \
  --corridor-name "$CORRIDOR_NAME" \
  --window "$STREET_WINDOW"

if ! grep -q '<vehicle' "$STREET_OUT"; then
  echo "ERROR: $STREET_OUT has no <vehicle> entries after export" >&2
  exit 1
fi

echo "OK: SUMO will use MATSim demand via:"
echo "  city:   $CITY_OUT"
echo "  street: $STREET_OUT (wired in streets/karla-marksa/config/simulation.sumocfg)"
