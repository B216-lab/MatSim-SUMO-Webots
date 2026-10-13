"""
City-wide TraCI metrics collector.
Used in CI city:simulate job.
Connects to SUMO TraCI server running in the same container on localhost:8813.
Outputs metrics.json to stdout.
"""
import json
import os
import traci

TRACI_PORT = int(os.getenv("TRACI_PORT", "8813"))


def run():
    traci.init(host="localhost", port=TRACI_PORT)

    steps = []
    step = 0

    try:
        while traci.simulation.getMinExpectedNumber() > 0:
            traci.simulationStep()
            step += 1

            if step % 120 == 0:  # every 60 sim-seconds (step-length=0.5)
                vehicles = traci.vehicle.getIDList()
                n = len(vehicles)
                avg_speed = (
                    sum(traci.vehicle.getSpeed(v) for v in vehicles) / max(n, 1)
                )
                halting = sum(1 for v in vehicles if traci.vehicle.getSpeed(v) < 0.1)
                steps.append({
                    "sim_time": traci.simulation.getTime(),
                    "vehicles": n,
                    "avg_speed_ms": round(avg_speed, 2),
                    "halting": halting,
                })
    finally:
        traci.close()

    result = {
        "scope": "city",
        "total_steps": step,
        "steps": steps,
        "avg_speed_overall": round(
            sum(s["avg_speed_ms"] for s in steps) / max(len(steps), 1), 2
        ),
        "peak_vehicles": max((s["vehicles"] for s in steps), default=0),
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    run()
