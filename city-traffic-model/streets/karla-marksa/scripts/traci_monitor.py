"""
TraCI мониторинг симуляции ул. Карла Маркса.
Собирает очереди у светофоров, среднюю скорость, corridor speed, halting.
Выводит metrics.json в stdout.
"""
import json
import os
import sys

import traci

SUMO_HOST = os.getenv("SUMO_HOST", "localhost")
TRACI_PORT = int(os.getenv("TRACI_PORT", "8817"))
SUMO_CONFIG = os.getenv("SUMO_CONFIG", "")
SUMO_BINARY = os.getenv("SUMO_BINARY", "sumo")
# If SUMO_CONFIG is set and no TraCI server is expected, start sumo locally.
LAUNCH_LOCAL = os.getenv("LAUNCH_LOCAL", "0") == "1"


def _connect():
    if LAUNCH_LOCAL and SUMO_CONFIG:
        traci.start([SUMO_BINARY, "-c", SUMO_CONFIG, "--no-step-log", "true"])
    else:
        traci.init(host=SUMO_HOST, port=TRACI_PORT)


def _queue_lengths():
    """Sum of halting vehicles approaching each TLS-controlled junction."""
    queues = {}
    for tls_id in traci.trafficlight.getIDList():
        controlled = traci.trafficlight.getControlledLinks(tls_id)
        incoming = set()
        for links in controlled:
            for link in links:
                if link:
                    incoming.add(link[0])  # incoming lane
        halting = 0
        for lane in incoming:
            try:
                halting += traci.lane.getLastStepHaltingNumber(lane)
            except traci.TraCIException:
                pass
        queues[tls_id] = halting
    return queues


def _corridor_edges():
    """Edges named ул. Карла Маркса (or latin variants) via SUMO street names."""
    edges = []
    keys = ("маркса", "marx", "marksa")
    for eid in traci.edge.getIDList():
        if eid.startswith(":"):
            continue
        name = ""
        try:
            name = (traci.edge.getStreetName(eid) or "").lower()
        except traci.TraCIException:
            pass
        if any(k in name for k in keys):
            edges.append(eid)
    return edges


def run():
    _connect()

    corridor = _corridor_edges()
    metrics_per_step = []
    step = 0

    try:
        while traci.simulation.getMinExpectedNumber() > 0:
            traci.simulationStep()
            step += 1
            sim_time = traci.simulation.getTime()

            if step % 60 == 0:  # every 30 sim-seconds at step-length 0.5
                vehicles = traci.vehicle.getIDList()
                n = len(vehicles)
                avg_speed = (
                    sum(traci.vehicle.getSpeed(v) for v in vehicles) / max(n, 1)
                )
                halting = sum(
                    1 for v in vehicles if traci.vehicle.getSpeed(v) < 0.1
                )
                queues = _queue_lengths()
                corridor_speed = 0.0
                if corridor:
                    speeds = []
                    for e in corridor:
                        try:
                            speeds.append(traci.edge.getLastStepMeanSpeed(e))
                        except traci.TraCIException:
                            pass
                    if speeds:
                        corridor_speed = sum(speeds) / len(speeds)

                metrics_per_step.append({
                    "sim_time": sim_time,
                    "vehicles": n,
                    "avg_speed_ms": round(avg_speed, 2),
                    "halting": halting,
                    "queue_length_per_tls": queues,
                    "total_queue": sum(queues.values()),
                    "corridor_mean_speed_ms": round(corridor_speed, 2),
                    "corridor_edges": len(corridor),
                })

            # Soft end if config duration exceeded when launched remotely without end
            if sim_time >= float(os.getenv("SIM_END", "3600")):
                break
    finally:
        traci.close()

    summary = {
        "scope": "street",
        "street": "karla-marksa",
        "total_steps": step,
        "steps": metrics_per_step,
        "avg_speed_overall": round(
            sum(m["avg_speed_ms"] for m in metrics_per_step)
            / max(len(metrics_per_step), 1),
            2,
        ),
        "peak_vehicles": max((m["vehicles"] for m in metrics_per_step), default=0),
        "peak_queue": max((m["total_queue"] for m in metrics_per_step), default=0),
        "avg_corridor_speed_ms": round(
            sum(m["corridor_mean_speed_ms"] for m in metrics_per_step)
            / max(len(metrics_per_step), 1),
            2,
        ),
    }
    out = json.dumps(summary, indent=2, ensure_ascii=False)
    metrics_path = os.getenv("METRICS_OUT")
    if metrics_path:
        with open(metrics_path, "w", encoding="utf-8") as fh:
            fh.write(out + "\n")
    # Ensure only JSON hits stdout (TraCI may print retry lines earlier)
    sys.stdout.write(out + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    try:
        run()
    except Exception as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)
