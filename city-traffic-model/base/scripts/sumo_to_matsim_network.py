#!/usr/bin/env python3
"""Convert a SUMO .net.xml into a MATSim network_v2 XML (same link/node IDs)."""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, "/usr/share/sumo/tools")
import sumolib  # noqa: E402


def lane_capacity(edge) -> float:
    # vehicles/hour; SUMO lane typically ~1800–2000 for urban
    return max(1, edge.getLaneNumber()) * 1800.0


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--sumo-net", required=True)
    p.add_argument("--out", required=True)
    args = p.parse_args()

    net = sumolib.net.readNet(args.sumo_net)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE network SYSTEM "http://www.matsim.org/files/dtd/network_v2.dtd">',
        '<network name="irkutsk-central">',
        '  <attributes>',
        '    <attribute name="coordinateReferenceSystem" class="java.lang.String">EPSG:32647</attribute>',
        "  </attributes>",
        "  <nodes>",
    ]
    for node in net.getNodes():
        x, y = node.getCoord()
        lines.append(f'    <node id="{node.getID()}" x="{x:.3f}" y="{y:.3f}"/>')
    lines.append("  </nodes>")
    lines.append("  <links capperiod=\"01:00:00\">")

    for edge in net.getEdges():
        if edge.getID().startswith(":"):
            continue
        # Skip pure pedestrian/bike if no passenger permission
        allow = edge.allows("passenger")
        if not allow:
            continue
        length = max(edge.getLength(), 1.0)
        speed = max(edge.getSpeed(), 1.0)
        lanes = max(edge.getLaneNumber(), 1)
        frm = edge.getFromNode().getID()
        to = edge.getToNode().getID()
        cap = lane_capacity(edge)
        lines.append(
            f'    <link id="{edge.getID()}" from="{frm}" to="{to}" '
            f'length="{length:.2f}" capacity="{cap:.1f}" '
            f'freespeed="{speed:.3f}" permlanes="{lanes}" modes="car"/>'
        )

    lines.append("  </links>")
    lines.append("</network>")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
