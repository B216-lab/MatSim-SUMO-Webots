#!/usr/bin/env python3
"""Generate a minimal synthetic MATSim population from a SUMO network.

Picks random fringe/building-proximate edges as home/work activity locations.
"""
from __future__ import annotations

import argparse
import random
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, "/usr/share/sumo/tools")
import sumolib  # noqa: E402


def edge_midpoint(edge):
    shape = edge.getShape()
    if not shape:
        return edge.getFromNode().getCoord()
    mid = shape[len(shape) // 2]
    return mid


def matsim_link_ids(path: Path) -> set[str]:
    """Link IDs from a MATSim network.xml (after NetworkCleaner, etc.)."""
    root = ET.parse(path).getroot()
    ids: set[str] = set()
    for el in root.iter():
        tag = el.tag.rsplit("}", 1)[-1]
        if tag == "link":
            lid = el.get("id")
            if lid:
                ids.add(lid)
    return ids


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--sumo-net", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--agents", type=int, default=400)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--corridor-name", default="Маркса")
    p.add_argument(
        "--matsim-network",
        help="If set, only place activities on link IDs present in this MATSim network",
    )
    args = p.parse_args()

    rng = random.Random(args.seed)
    net = sumolib.net.readNet(args.sumo_net)
    edges = [
        e
        for e in net.getEdges()
        if not e.getID().startswith(":") and e.allows("passenger") and e.getLength() > 20
    ]
    if args.matsim_network:
        allowed = matsim_link_ids(Path(args.matsim_network))
        if not allowed:
            raise SystemExit(f"No links found in MATSim network: {args.matsim_network}")
        edges = [e for e in edges if e.getID() in allowed]
        if not edges:
            raise SystemExit(
                "No SUMO edges remain after filtering to cleaned MATSim link IDs"
            )
    corridor = [e for e in edges if args.corridor_name in (e.getName() or "")]
    if not corridor:
        corridor = edges

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v6.dtd">',
        f'<population desc="synthetic-irkutsk-demo n={args.agents}">',
    ]

    for i in range(args.agents):
        home_e = rng.choice(edges)
        # Bias work trips toward corridor for street demand
        work_e = rng.choice(corridor if rng.random() < 0.55 else edges)
        hx, hy = edge_midpoint(home_e)
        wx, wy = edge_midpoint(work_e)
        dep_h = 7 + rng.randint(0, 1)
        dep_m = rng.randint(0, 59)
        ret_h = 17 + rng.randint(0, 1)
        ret_m = rng.randint(0, 59)
        lines.append(f'  <person id="p{i}">')
        lines.append('    <plan selected="yes">')
        lines.append(
            f'      <activity type="home" link="{home_e.getID()}" x="{hx:.2f}" y="{hy:.2f}" '
            f'end_time="{dep_h:02d}:{dep_m:02d}:00"/>'
        )
        lines.append('      <leg mode="car"/>')
        lines.append(
            f'      <activity type="work" link="{work_e.getID()}" x="{wx:.2f}" y="{wy:.2f}" '
            f'end_time="{ret_h:02d}:{ret_m:02d}:00"/>'
        )
        lines.append('      <leg mode="car"/>')
        lines.append(
            f'      <activity type="home" link="{home_e.getID()}" x="{hx:.2f}" y="{hy:.2f}"/>'
        )
        lines.append("    </plan>")
        lines.append("  </person>")

    lines.append("</population>")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out} with {args.agents} agents")


if __name__ == "__main__":
    main()
