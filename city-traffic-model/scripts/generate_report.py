"""
Генерирует HTML-отчёт из metrics.json.
Использование: python3 generate_report.py --metrics path/to/metrics.json --street lenina --output report.html
"""
import argparse
import json
import sys
from pathlib import Path


def generate(metrics_path: str, street: str, output_path: str) -> None:
    with open(metrics_path) as f:
        m = json.load(f)

    rows = "".join(
        f"<tr><td>{s['sim_time']:.0f}</td><td>{s['vehicles']}</td>"
        f"<td>{s['avg_speed_ms']}</td><td>{s['halting']}</td></tr>"
        for s in m.get("steps", [])
    )

    html = f"""<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Simulation Report — {street}</title>
  <style>
    body {{ font-family: sans-serif; max-width: 900px; margin: 2rem auto; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #ccc; padding: 6px 10px; text-align: right; }}
    th {{ background: #f0f0f0; }}
    .summary {{ background: #f9f9f9; padding: 1rem; border-radius: 4px; margin-bottom: 1rem; }}
  </style>
</head>
<body>
  <h1>Симуляция: {street}</h1>
  <div class="summary">
    <p><b>Всего шагов:</b> {m.get('total_steps', '—')}</p>
    <p><b>Средняя скорость:</b> {m.get('avg_speed_overall', '—')} м/с</p>
    <p><b>Пиковое число ТС:</b> {m.get('peak_vehicles', '—')}</p>
  </div>
  <table>
    <thead><tr><th>Время (с)</th><th>ТС</th><th>Ср. скорость (м/с)</th><th>Стоят</th></tr></thead>
    <tbody>{rows}</tbody>
  </table>
</body>
</html>"""

    Path(output_path).write_text(html, encoding="utf-8")
    print(f"Report written to {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--metrics", required=True)
    parser.add_argument("--street", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    generate(args.metrics, args.street, args.output)
