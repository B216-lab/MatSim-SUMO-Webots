#!/usr/bin/env bash
# Sync SUMO files into worlds/karla_marksa_net for WeBots SumoInterface.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NET_DIR="${STREET_DIR}/worlds/karla_marksa_net"
WORLD_FILE="${STREET_DIR}/worlds/karla_marksa.wbt"

mkdir -p "$NET_DIR"

cp -f "${STREET_DIR}/network/karla_marksa.net.xml" "${NET_DIR}/sumo.net.xml"

# TraCI returns local net coords (convBoundary), but sumo_supervisor adds -netOffset.
# UTM-scale offsets push vehicles hundreds of km from the WeBots origin; zero for WeBots copy.
sed -i 's/netOffset="[^"]*"/netOffset="0.00,0.00"/' "${NET_DIR}/sumo.net.xml"

# demand_mode from simulation.yml (default matsim for this street).
DEMAND_MODE="$(
  awk -F: '/^demand_mode:/{gsub(/[[:space:]]/, "", $2); print $2; exit}' \
    "${STREET_DIR}/config/simulation.yml" 2>/dev/null || true
)"
DEMAND_MODE="${DEMAND_MODE:-matsim}"
MATSIM_ROUTES="${STREET_DIR}/demand/street_matsim.rou.xml"
RANDOM_ROUTES="${STREET_DIR}/demand/street.rou.xml"

if [[ "$DEMAND_MODE" == "matsim" ]]; then
  if [[ ! -f "$MATSIM_ROUTES" ]] || ! grep -q '<vehicle' "$MATSIM_ROUTES"; then
    echo "ERROR: demand_mode=matsim but $MATSIM_ROUTES has no vehicles." >&2
    echo "Export MATSim plans first: ../../base/scripts/export_matsim_demand.sh" >&2
    exit 1
  fi
  cp -f "$MATSIM_ROUTES" "${NET_DIR}/sumo.rou.xml"
  echo "Using MATSim-filtered routes ($MATSIM_ROUTES)"
elif [[ -f "$MATSIM_ROUTES" ]] && grep -q '<vehicle' "$MATSIM_ROUTES"; then
  cp -f "$MATSIM_ROUTES" "${NET_DIR}/sumo.rou.xml"
  echo "Using MATSim-filtered routes ($MATSIM_ROUTES)"
else
  cp -f "$RANDOM_ROUTES" "${NET_DIR}/sumo.rou.xml"
  echo "Using randomTrips routes ($RANDOM_ROUTES)"
fi

# Optional PT stops
if [[ -f "${STREET_DIR}/demand/ptstops.xml" ]]; then
  cp -f "${STREET_DIR}/demand/ptstops.xml" "${NET_DIR}/ptstops.xml"
  ADDITIONAL="ptstops.xml"
else
  ADDITIONAL=""
fi

cat > "${NET_DIR}/sumo.sumocfg" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <input>
        <net-file value="sumo.net.xml"/>
        <route-files value="sumo.rou.xml"/>
$([ -n "$ADDITIONAL" ] && echo "        <additional-files value=\"${ADDITIONAL}\"/>")
    </input>
    <time>
        <begin value="0"/>
        <end value="3600"/>
        <step-length value="0.5"/>
    </time>
    <report>
        <no-step-log value="true"/>
        <no-warnings value="true"/>
    </report>
</configuration>
EOF

# Frame Viewpoint + ground over the full net so the MP4 covers the corridor.
if [[ -f "$WORLD_FILE" ]]; then
  python3 - "$NET_DIR/sumo.net.xml" "$WORLD_FILE" <<'PY'
import math, re, sys

net_path, world_path = sys.argv[1], sys.argv[2]
header = open(net_path, encoding="utf-8").read(8192)
m = re.search(r'convBoundary="([^"]+)"', header)
if not m:
    raise SystemExit(f"no convBoundary in {net_path}")
xmin, ymin, xmax, ymax = map(float, m.group(1).split(","))
cx, cy = (xmin + xmax) / 2.0, (ymin + ymax) / 2.0
w, h = xmax - xmin, ymax - ymin

# WeBots fieldOfView is vertical; CI records 1280x720 → aspect 16:9.
# Orientation matches WeBots default.wbt look-from-+Z (covers the XY SUMO plane).
vfov = 1.05
aspect = 1280.0 / 720.0
hfov = 2.0 * math.atan(math.tan(vfov / 2.0) * aspect)
margin = 1.30
z = max(
    (w * margin / 2.0) / math.tan(hfov / 2.0),
    (h * margin / 2.0) / math.tan(vfov / 2.0),
    500.0,
)
gw, gh = w * 1.20, h * 1.20
far = max(z * 5.0, math.hypot(w, h) * 2.0)

viewpoint = (
    "Viewpoint {\n"
    "  orientation -0.5773 0.5773 0.5773 2.0944\n"
    f"  position {cx:.2f} {cy:.2f} {z:.2f}\n"
    "  near 5\n"
    f"  far {far:.2f}\n"
    f"  fieldOfView {vfov:.3f}\n"
    "}"
)
ground = (
    "Solid {\n"
    f"  translation {cx:.2f} {cy:.2f} -0.05\n"
    "  children [\n"
    "    Shape {\n"
    "      appearance Appearance {\n"
    "        material Material {\n"
    "          diffuseColor 0.35 0.35 0.35\n"
    "        }\n"
    "      }\n"
    "      geometry Box {\n"
    f"        size {gw:.2f} {gh:.2f} 0.1\n"
    "      }\n"
    "    }\n"
    "  ]\n"
    "  name \"ground\"\n"
    "  boundingObject Box {\n"
    f"    size {gw:.2f} {gh:.2f} 0.1\n"
    "  }\n"
    "}"
)


def replace_node(src: str, node_name: str, replacement: str) -> str:
    key = node_name + " {"
    start = src.find(key)
    if start < 0:
        raise SystemExit(f"missing {node_name} in world")
    i = start + len(key) - 1  # at '{'
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[:start] + replacement + src[j + 1 :]
    raise SystemExit(f"unbalanced braces for {node_name}")


def replace_named_solid(src, solid_name, replacement):
    marker = f'name "{solid_name}"'
    mid = src.find(marker)
    if mid < 0:
        if replacement is None:
            return src
        raise SystemExit(f'missing Solid name "{solid_name}"')
    # Walk back to the Solid { that owns this name.
    start = src.rfind("Solid {", 0, mid)
    if start < 0:
        raise SystemExit(f'cannot find Solid for "{solid_name}"')
    i = start + len("Solid {") - 1
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                end = j + 1
                if replacement is None:
                    # Drop trailing newline if present.
                    if end < len(src) and src[end] == "\n":
                        end += 1
                    return src[:start] + src[end:]
                return src[:start] + replacement + src[end:]
    raise SystemExit(f'unbalanced Solid for "{solid_name}"')


world = open(world_path, encoding="utf-8").read()
world = replace_node(world, "Viewpoint", viewpoint)
world = replace_named_solid(world, "ground", ground)
for b in ("building_a", "building_b", "building_c"):
    world = replace_named_solid(world, b, None)

open(world_path, "w", encoding="utf-8").write(world)
print(
    f"Camera framed over net bounds "
    f"[{xmin:.0f},{ymin:.0f}]–[{xmax:.0f},{ymax:.0f}] "
    f"center=({cx:.0f},{cy:.0f}) height={z:.0f}m"
)
PY
fi

echo "OK: WeBots SUMO net ready at ${NET_DIR}"
