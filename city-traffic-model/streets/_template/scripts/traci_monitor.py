"""
TraCI мониторинг симуляции улицы.
Запускается как CI job, выводит metrics.json в stdout.
"""
import json
import sys
import os
import traci

SUMO_HOST = os.getenv("SUMO_HOST", "localhost")
TRACI_PORT = int(os.getenv("TRACI_PORT", "8813"))
SUMO_CONFIG = os.getenv("SUMO_CONFIG", "/scenario/config/simulation.sumocfg")


def run():
    traci.init(host=SUMO_HOST, port=TRACI_PORT)

    metrics_per_step = []
    step = 0

    try:
        while traci.simulation.getMinExpectedNumber() > 0:
            traci.simulationStep()
            step += 1

            if step % 60 == 0:  # каждые 30 секунд симуляции (step=0.5s)
                vehicles = traci.vehicle.getIDList()
                n = len(vehicles)
                avg_speed = (
                    sum(traci.vehicle.getSpeed(v) for v in vehicles) / max(n, 1)
                )
                halting = sum(
                    1 for v in vehicles if traci.vehicle.getSpeed(v) < 0.1
                )
                metrics_per_step.append({
                    "sim_time": traci.simulation.getTime(),
                    "vehicles": n,
                    "avg_speed_ms": round(avg_speed, 2),
                    "halting": halting,
                })
    finally:
        traci.close()

    summary = {
        "total_steps": step,
        "steps": metrics_per_step,
        "avg_speed_overall": round(
            sum(m["avg_speed_ms"] for m in metrics_per_step) / max(len(metrics_per_step), 1), 2
        ),
        "peak_vehicles": max((m["vehicles"] for m in metrics_per_step), default=0),
    }

    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    run()
