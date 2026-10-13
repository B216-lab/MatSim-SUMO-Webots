# city-traffic-model

Транспортная модель Иркутска. Стек: MATSim → SUMO → WeBots.

## Активный сценарий: ул. Карла Маркса

Bbox: `104.278,52.278,104.312,52.291` · TraCI port: `8817`

```bash
cd streets/karla-marksa

# 1. OSM → сеть (нужен curl + netconvert)
./scripts/fetch_osm.sh
./scripts/build_network.sh

# 2. Спрос: MATSim-filtered routes (demand/street_matsim.rou.xml)
#    Optional randomTrips smoke: ./scripts/gen_demand.sh → street.rou.xml

# 3. Smoke test 60 сек
sumo -c config/simulation.sumocfg --end 60 --no-step-log

# 4. Метрики TraCI
PYTHONPATH=/usr/share/sumo/tools \
  LAUNCH_LOCAL=1 SUMO_CONFIG=config/simulation.sumocfg SIM_END=60 \
  python3 scripts/traci_monitor.py | tee output/metrics.json
```

Docker smoke:

```bash
docker run --rm \
  -v $(pwd)/streets/karla-marksa:/scenario \
  traffic-sim/sumo:1.27.1 \
  sumo --configuration-file /scenario/config/simulation.sumocfg --end 60 --no-step-log
```

## Структура

```
city-traffic-model/
├── base/                        # MVP placeholder (not a full-city OSM extract yet)
│   ├── network/
│   │   └── irkutsk.net.xml      # Currently a copy of karla-marksa.net.xml
│   ├── demand/
│   │   └── irkutsk.rou.xml      # Спрос (MATSim output или activitygen)
│   └── matsim/
│       └── config.xml           # Конфиг MATSim batch прогона
├── streets/
│   ├── _template/               # Шаблон для новой улицы
│   └── karla-marksa/            # ул. Карла Маркса
│       ├── config/
│       │   ├── simulation.sumocfg
│       │   └── simulation.yml   # bbox, duration, demand_mode
│       ├── network/
│       ├── demand/
│       ├── osm/
│       ├── worlds/
│       │   └── karla_marksa.wbt # WeBots (SumoInterface)
│       └── scripts/
├── scripts/
│   └── generate_report.py
└── .gitlab-ci.yml
```

## Добавить новую улицу

```bash
cp -r streets/_template streets/novaya-street
# Заполнить streets/novaya-street/config/simulation.yml
# Добавить блок CI jobs в .gitlab-ci.yml
git add streets/novaya-street
git commit -m "feat: add novaya-street scenario"
```

## CI/CD

| Триггер | Jobs |
|---|---|
| push в `streets/karla-marksa/**` | validate → simulate → report (+ sumo-visualize / visualize manual) |
| push в `base/**` | city:validate → city:simulate |
| Ручной запуск (web) | любой job, включая city:matsim |

Runner: self-hosted на `webots-vm`, Docker executor (`pull_policy=if-not-present`).

### Visual artifacts (manual)

Street demand for simulate / visuals is **MATSim-filtered** (`demand/street_matsim.rou.xml`), not randomTrips.

**SUMO GUI MP4** — `karla-marksa:sumo-visualize` → `output/karla-marksa/sumo_simulation.mp4`

```bash
cd docker && make build-sumo   # traffic-sim/sumo:1.27.1 (needs ffmpeg)
cd ../city-traffic-model/streets/karla-marksa
./scripts/record_sumo_gui.sh --seconds 60 --output /tmp/sumo_simulation.mp4
```

**WeBots MP4** — `karla-marksa:visualize` → `output/karla-marksa/simulation.mp4`

Requires a rebuilt WeBots image with ffmpeg + recording entrypoint and SUMO 1.27 (PPA),
matching `traffic-sim/sumo` — Ubuntu’s default SUMO 1.18 cannot load these nets:

```bash
cd docker && make build-webots   # traffic-sim/webots:R2023b
```

Recording is driven by env vars in `docker/webots/entrypoint.sh`:

- `WEBOTS_RECORD_MP4` — output path (set by CI)
- `WEBOTS_RECORD_SECONDS` — clip length (CI default: 300)
- `SCREEN_RES` — Xvfb / ffmpeg size (CI default: `1280x720x24`)

Karla-marksa simulate / visual jobs use `SIM_END` / record length **300s** so enough MATSim vehicles appear (sparse in the first minute).

If `karla-marksa:visualize` fails at artifact upload with **HTTP 413**, raise `nginx['client_max_body_size']` on the GitLab server (`ilab-irk.ru`) — see `wiki/projects/traffic-sim/gitlab-artifact-upload-limits.md`. Do not shorten the recording to work around a 1 MB nginx default.

Without `WEBOTS_RECORD_MP4`, the entrypoint keeps the long-running stream mode for interactive user stacks.

## Документация

- `wiki/projects/traffic-sim/workflow.md` — роли инструментов
- `wiki/projects/traffic-sim/Irkutsk-architecture.md` — архитектура
- `proposition.md` — обоснование выбора улицы

## MATSim demand (phase 2)

Street SUMO (`config/simulation.sumocfg`) and WeBots sync use
`demand/street_matsim.rou.xml` (MATSim-exported routes). City SUMO uses
`base/demand/irkutsk.rou.xml`. Regenerate both after a MATSim run:

```bash
AGENTS=300 ITERS=3 ./base/scripts/prepare_matsim.sh
mkdir -p base/matsim/output
docker run --rm \
  -v "$PWD/base/matsim:/matsim/input:ro" \
  -v "$PWD/base/matsim/output:/matsim/output" \
  -e MATSIM_CONFIG=/matsim/input/config.xml -e MATSIM_HEAP=4g \
  traffic-sim/matsim:15.0
./base/scripts/export_matsim_demand.sh
```

## WeBots 3D (phase 3)

```bash
cd streets/karla-marksa
./scripts/sync_webots_net.sh
./scripts/run_webots.sh
```

WeBots image includes SUMO. Default stream host port `1240`, viewer `18081`.
