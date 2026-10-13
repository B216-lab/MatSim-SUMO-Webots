#!/usr/bin/env python3
"""Convert MATSim output plans (with routes) → SUMO routes, optionally corridor-filtered."""
from __future__ import annotations

import argparse
import gzip
import xml.etree.ElementTree as ET
from pathlib import Path


def open_xml(path: Path):
    if str(path).endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8")
    return path.open("r", encoding="utf-8")


def parse_time(t: str) -> float:
    # HH:MM:SS or seconds
    if ":" in t:
        parts = [float(x) for x in t.split(":")]
        if len(parts) == 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        return parts[0] * 60 + parts[1]
    return float(t)


def corridor_edges_from_sumo_net(net_path: Path, name_substr: str) -> set[str]:
    """Edge IDs whose street name contains name_substr (case-insensitive)."""
    needle = name_substr.casefold()
    root = ET.parse(net_path).getroot()
    edges: set[str] = set()
    for el in root.iter():
        tag = el.tag.rsplit("}", 1)[-1]
        if tag != "edge":
            continue
        eid = el.get("id") or ""
        if not eid or eid.startswith(":"):
            continue
        name = (el.get("name") or "").casefold()
        if needle in name:
            edges.add(eid)
    return edges


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--plans", required=True, help="MATSim output_plans.xml(.gz)")
    p.add_argument("--out", required=True)
    p.add_argument(
        "--corridor-edges",
        default="",
        help="Comma-separated edge ids; keep trips intersecting any",
    )
    p.add_argument(
        "--corridor-file",
        default="",
        help="File with comma- or newline-separated edge ids (avoids CLI dash issues)",
    )
    p.add_argument(
        "--sumo-net",
        default="",
        help="SUMO .net.xml used with --corridor-name to select corridor edges",
    )
    p.add_argument(
        "--corridor-name",
        default="Маркса",
        help="Substring matched against SUMO edge name= (with --sumo-net)",
    )
    p.add_argument("--remap-begin", type=float, default=0.0,
                   help="Shift departures so min depart maps near this (optional)")
    p.add_argument("--window", type=float, default=3600.0,
                   help="Only keep trips with depart in [remap_begin, remap_begin+window] after shift")
    args = p.parse_args()

    corridor = set()
    if args.corridor_file:
        raw = Path(args.corridor_file).read_text(encoding="utf-8")
        for part in raw.replace("\n", ",").split(","):
            part = part.strip()
            if part:
                corridor.add(part)
    if args.corridor_edges:
        corridor.update(e for e in args.corridor_edges.split(",") if e)
    if args.sumo_net:
        from_net = corridor_edges_from_sumo_net(Path(args.sumo_net), args.corridor_name)
        if not from_net:
            raise SystemExit(
                f"No corridor edges in {args.sumo_net} matching name '{args.corridor_name}'"
            )
        corridor.update(from_net)
        print(f"Corridor edges from net: {len(from_net)}", flush=True)

    vehicles = []
    with open_xml(Path(args.plans)) as fh:
        # Iterparse for large files
        context = ET.iterparse(fh, events=("end",))
        for event, elem in context:
            if elem.tag != "person":
                continue
            pid = elem.get("id")
            plan = None
            for child in elem:
                if child.tag == "plan" and child.get("selected") in (None, "yes", "true"):
                    plan = child
                    break
            if plan is None:
                elem.clear()
                continue

            # Walk legs with routes
            leg_idx = 0
            for child in plan:
                if child.tag != "leg":
                    continue
                if child.get("mode") not in (None, "car", "ride"):
                    continue
                route = None
                for sub in child:
                    if sub.tag == "route":
                        route = sub
                        break
                if route is None or not (route.text or "").strip():
                    continue
                links = (route.text or "").split()
                if corridor and not any(l in corridor for l in links):
                    continue
                dep = child.get("dep_time") or child.get("departure")
                if dep is None:
                    # fall back to previous activity end_time — skip if unknown
                    continue
                depart = parse_time(dep)
                vehicles.append((pid, leg_idx, depart, links))
                leg_idx += 1
            elem.clear()

    if not vehicles:
        print("WARNING: no vehicles extracted", flush=True)

    # Remap morning peak into [0, window] for street scenario
    if vehicles:
        min_dep = min(v[2] for v in vehicles)
        # Prefer keep absolute times if already in window; else shift
        shifted = []
        for pid, leg_idx, depart, links in vehicles:
            d = depart - min_dep + args.remap_begin
            if 0 <= d <= args.window * 3:  # keep a few hours
                shifted.append((pid, leg_idx, d, links))
        vehicles = shifted

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<routes>",
        '  <vType id="car" accel="2.6" decel="4.5" sigma="0.5" length="5" maxSpeed="50"/>',
    ]
    kept = []
    for i, (pid, leg_idx, depart, links) in enumerate(vehicles):
        if depart > args.window:
            continue
        kept.append((pid, leg_idx, depart, links))

    for pid, leg_idx, depart, links in kept:
        rid = f"r_{pid}_{leg_idx}"
        lines.append(f'  <route id="{rid}" edges="{" ".join(links)}"/>')
    for pid, leg_idx, depart, links in kept:
        rid = f"r_{pid}_{leg_idx}"
        vid = f"m_{pid}_{leg_idx}"
        lines.append(f'  <vehicle id="{vid}" type="car" depart="{depart:.1f}" route="{rid}"/>')
    lines.append("</routes>")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out} with {len(kept)} vehicles")


if __name__ == "__main__":
    main()
