# Docker-окружение: MATSim + SUMO + WeBots

Изолированные контейнерные стеки для каждого разработчика на общем сервере.
Все контейнеры подключены к сети `sim-shared` и видят друг друга по DNS-именам.

> Полный runbook с инструкциями по добавлению новых контейнеров:
> [`wiki/projects/traffic-sim/docker-setup.md`](../wiki/projects/traffic-sim/docker-setup.md)

## Структура

```
docker/
├── infrastructure/         # Общая сеть sim-shared (запустить один раз)
├── sumo/                   # SUMO 1.27.1 + TraCI
├── matsim/                 # MATSim 15.0 (Java 17)
├── webots/                 # WeBots R2023b + Xvfb + web streaming
└── user-template/          # Шаблон стека для одного пользователя
```

## Первый запуск (администратор, один раз)

```bash
# 1. Установить Docker Engine
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker

# 2. Создать общую сеть
make network-up

# 3. Собрать образы (traffic-sim/sumo:1.27.1, traffic-sim/matsim:15.0, traffic-sim/webots:R2023b)
make build
```

## Запуск пользовательского стека

```bash
# Скопировать шаблон .env и заполнить
cp docker/user-template/.env.example docker/user-template/.env
# Отредактировать: USER_PREFIX, STREAM_HOST_PORT, TRACI_HOST_PORT, VIEWER_HOST_PORT

# Поднять свой стек (из каталога docker/)
make up
```

Администратор может поднять все стеки: `make admin-up-all`.

## Распределение портов

| Пользователь | WeBots stream | SUMO TraCI | Viewer | noVNC |
|---|---|---|---|---|
| korolenkoelizaveta | 1234 | 8813 | 8080 | 6080 |
| ruslanmuhamed123 | 1235 | 8814 | 8081 | 6081 |
| kravectrofim | 1236 | 8815 | 8082 | 6082 |
| ubuntu | 1237 | 8816 | 8083 | 6090 |

## Межпользовательская коммуникация

Все контейнеры в сети `sim-shared` адресуются по имени:

```python
# Python: подключиться к TraCI другого пользователя
import traci
traci.init(host="ruslanmuhamed123-sumo", port=8813)
```

```bash
# Проверить видимость
docker exec korolenkoelizaveta-webots ping ruslanmuhamed123-sumo
```

## Статус и логи

```bash
make status          # все запущенные контейнеры симуляции
make logs            # логи своего стека (follow)
make network-status  # IP-адреса контейнеров в sim-shared
```

## MATSim (пакетный прогон)

MATSim запускается по требованию через `--profile matsim` (не зависит от SUMO):

```bash
USER_PREFIX=korolenkoelizaveta docker compose -f docker/user-template/docker-compose.yml \
  --profile matsim run matsim
```

## WeBots web streaming

После запуска стека откройте в браузере:

```
http://<tailscale-ip>:<STREAM_HOST_PORT>
```

Либо HTML viewer (если проброшен `VIEWER_HOST_PORT`):

```
http://<tailscale-ip>:<VIEWER_HOST_PORT>/?host=<tailscale-ip>&port=<STREAM_HOST_PORT>
```
