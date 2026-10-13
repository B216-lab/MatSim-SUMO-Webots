#!/usr/bin/env bash
# Generate random peak-hour demand for ул. Карла Маркса.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NET="${STREET_DIR}/network/karla_marksa.net.xml"
DEMAND_DIR="${STREET_DIR}/demand"
TRIPS_AM="${DEMAND_DIR}/trips_am.rou.xml"
TRIPS_PM="${DEMAND_DIR}/trips_pm.rou.xml"
ROUTES_OUT="${DEMAND_DIR}/street.rou.xml"
ADDITIONAL_OUT="${DEMAND_DIR}/additional.xml"
PT_OUT="${DEMAND_DIR}/pt.rou.xml"

SUMO_TOOLS="${SUMO_HOME:-/usr/share/sumo}/tools"
RANDOM_TRIPS="${SUMO_TOOLS}/randomTrips.py"

if [[ ! -f "$NET" ]]; then
  echo "Missing network: $NET — run build_network.sh first" >&2
  exit 1
fi
if [[ ! -f "$RANDOM_TRIPS" ]]; then
  echo "Missing randomTrips.py at $RANDOM_TRIPS" >&2
  exit 1
fi

mkdir -p "$DEMAND_DIR"

# Morning peak 07:00–09:00 (25200–32400s) — denser insertion
python3 "$RANDOM_TRIPS" \
  -n "$NET" \
  -o "$TRIPS_AM" \
  -r "${DEMAND_DIR}/routes_am.rou.xml" \
  -b 25200 -e 32400 \
  -p 2.5 \
  --vehicle-class passenger \
  --prefix am \
  --validate \
  --fringe-factor 5 \
  --seed 42

# Evening peak 17:00–19:00 (61200–68400s)
python3 "$RANDOM_TRIPS" \
  -n "$NET" \
  -o "$TRIPS_PM" \
  -r "${DEMAND_DIR}/routes_pm.rou.xml" \
  -b 61200 -e 68400 \
  -p 2.5 \
  --vehicle-class passenger \
  --prefix pm \
  --validate \
  --fringe-factor 5 \
  --seed 43

# For street sumocfg we run a 3600s window starting at 0 for smoke/demo.
# Remap morning peak into [0, 3600] for the default scenario.
python3 "$RANDOM_TRIPS" \
  -n "$NET" \
  -o "${DEMAND_DIR}/trips_demo.rou.xml" \
  -r "$ROUTES_OUT" \
  -b 0 -e 3600 \
  -p 1.5 \
  --vehicle-class passenger \
  --prefix km \
  --validate \
  --fringe-factor 5 \
  --seed 44

# Minimal additional file (stops / detectors can be filled later)
cat > "$ADDITIONAL_OUT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<additional>
    <!-- Placeholder for detectors, busStops, induction loops -->
</additional>
EOF

# Empty PT routes stub — not referenced by simulation.sumocfg yet (PT not modeled).
cat > "$PT_OUT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<routes xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="http://sumo.dlr.de/xsd/routes_file.xsd">
    <!-- Tram/bus routes — populate from OSM ptlines / GTFS -->
</routes>
EOF

echo "OK: routes=${ROUTES_OUT}"
echo "OK: additional=${ADDITIONAL_OUT}"
echo "OK: peak AM=${DEMAND_DIR}/routes_am.rou.xml PM=${DEMAND_DIR}/routes_pm.rou.xml"
