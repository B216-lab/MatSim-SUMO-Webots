#!/usr/bin/env bash
# Rewrite demand/street_bounds.poly.xml from network convBoundary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NET="${STREET_DIR}/network/karla_marksa.net.xml"
OUT="${STREET_DIR}/demand/street_bounds.poly.xml"

[[ -f "$NET" ]] || { echo "Net not found: $NET" >&2; exit 1; }

python3 - "$NET" "$OUT" <<'PY'
import re, sys

net_path, out_path = sys.argv[1], sys.argv[2]
header = open(net_path, encoding="utf-8").read(8192)
m = re.search(r'convBoundary="([^"]+)"', header)
if not m:
    raise SystemExit(f"no convBoundary in {net_path}")
xmin, ymin, xmax, ymax = (float(x) for x in m.group(1).split(","))
shape = (
    f"{xmin:.2f},{ymin:.2f} "
    f"{xmax:.2f},{ymin:.2f} "
    f"{xmax:.2f},{ymax:.2f} "
    f"{xmin:.2f},{ymax:.2f} "
    f"{xmin:.2f},{ymin:.2f}"
)
open(out_path, "w", encoding="utf-8").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    "<additional>\n"
    '  <poly id="street_bounds" type="street_bounds"\n'
    '        color="0,0.75,1,0.22" fill="1" layer="1" lineWidth="40"\n'
    f'        shape="{shape}"/>\n'
    "</additional>\n"
)
print(f"Wrote {out_path} from convBoundary [{xmin:.2f},{ymin:.2f}]–[{xmax:.2f},{ymax:.2f}]")
PY
