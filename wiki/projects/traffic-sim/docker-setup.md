# Docker: запуск симуляционного стека

> Стек: MATSim + SUMO + WeBots.  
> Исходники конфигов: [`docker/`](../../../docker/)

---

## 0. Предварительные условия

- Docker Engine ≥ 26 установлен на сервере
- Сеть `sim-shared` создана администратором (см. раздел «Первый запуск»)
- Вы подключены к серверу по SSH через Tailscale

---

## 1. Первый запуск сервера (администратор, один раз)

```bash
# Установить Docker Engine
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker

# Создать общую сеть
cd ~/citytraffic/docker
make network-up

# Собрать образы (выполняется один раз; каждый пользователь может сделать это сам)
make build
```

После `make network-up` сеть `sim-shared` существует постоянно — все контейнеры, подключённые к ней, видят друг друга по DNS-имени.

Когда у пользователя появился доступ по SSH и его `~/citytraffic/docker/user-template/.env` настроен, поднять его стек может как он сам, так и администратор:

```bash
# Администратор, поднять все стеки разом
make admin-up-all

# Администратор, остановить все стеки
make admin-down-all
```

---

## 2. Запуск своего стека

Репозиторий находится у каждого пользователя в `~/citytraffic`.
Все команды выполняются из `~/citytraffic/docker/`.

### 2.1 Настроить `.env`

```bash
cd ~/citytraffic/docker
nano user-template/.env
```

Файл `user-template/.env` не существует до первого редактирования — он создаётся автоматически из шаблона при первом `make up` с подсказкой что изменить. Можно также создать вручную: `cp user-template/.env.example user-template/.env`.

Заменить значения под себя:

| Переменная | Что задать |
|---|---|
| `USER_PREFIX` | Своё имя пользователя на сервере (`korolenkoelizaveta`, `ruslanmuhamed123`, `kravectrofim`) |
| `STREAM_HOST_PORT` | Уникальный порт для WeBots streaming |
| `TRACI_HOST_PORT` | Уникальный порт для SUMO TraCI |

Распределение портов:

| Пользователь | `STREAM_HOST_PORT` | `TRACI_HOST_PORT` | `VIEWER_HOST_PORT` | `SUMO_NOVNC_HOST_PORT` | `NOVNC_HOST_PORT` |
|---|---|---|---|---|---|
| korolenkoelizaveta | 1234 | 8813 | 8080 | 6083 | 6080 |
| ruslanmuhamed123 | 1235 | 8814 | 8081 | 6084 | 6081 |
| kravectrofim | 1236 | 8815 | 8082 | 6085 | 6082 |
| ubuntu | 1237 | 8816 | 8083 | 6086 | 6090 |

### 2.2 Поднять контейнеры

```bash
cd ~/citytraffic/docker
make up
```

Запущенные сервисы:

| Контейнер | Назначение | Адрес для других пользователей |
|---|---|---|
| `korolenkoelizaveta-sumo` | TraCI-сервер | `korolenkoelizaveta-sumo:8813` |
| `korolenkoelizaveta-webots` | 3D-симуляция, streaming | `korolenkoelizaveta-webots:1234` |
| `korolenkoelizaveta-matsim` | Batch-прогон (по запросу) | `korolenkoelizaveta-matsim` |

### 2.3 Открыть WeBots в браузере

```
http://<tailscale-ip>:<STREAM_HOST_PORT>
```

---

## 3. Ежедневные команды

Все команды выполняются из `~/citytraffic/docker/`.

```bash
make up            # поднять свой стек
make down          # остановить
make restart       # перезапустить (down + up)
make logs          # логи (follow, Ctrl+C для выхода)
make status        # все запущенные контейнеры симуляции
make network-status  # IP-адреса в сети sim-shared

# Перезапустить один сервис
docker restart korolenkoelizaveta-sumo
```

---

## 4. Межпользовательская коммуникация

Все контейнеры в `sim-shared` адресуются по имени `<USER_PREFIX>-<service>`:

```python
# Python: подключиться к TraCI другого пользователя
import traci
traci.init(host="ruslanmuhamed123-sumo", port=8813)

# Проверить связь из своего контейнера
docker exec korolenkoelizaveta-webots ping ruslanmuhamed123-sumo
```

```bash
# WebSocket WeBots другого пользователя (порт — его STREAM_HOST_PORT)
curl http://kravectrofim-webots:1234/
```

---

## 5. Запуск MATSim (batch-прогон)

MATSim не запускается автоматически — только по явному вызову:

```bash
# Разовый запуск сценария
cd ~/citytraffic/docker
docker compose --env-file user-template/.env \
  -f user-template/docker-compose.yml \
  --profile matsim run --rm matsim

# Результаты окажутся в MATSIM_OUTPUT (по умолчанию ./matsim-output/)
```

---

## 6. Добавление нового контейнера в стек

### 6.1 Добавить сервис к существующему пользовательскому стеку

Открыть `docker/user-template/docker-compose.yml` и добавить блок в `services:`:

```yaml
services:
  # ... существующие sumo, matsim, webots ...

  my-agent:
    image: python:3.12-slim          # или build: ../my-agent/
    container_name: "${USER_PREFIX:-dev}-my-agent"
    hostname: "${USER_PREFIX:-dev}-my-agent"
    restart: unless-stopped
    environment:
      SUMO_HOST: "${USER_PREFIX:-dev}-sumo"
      SUMO_PORT: "8813"
    volumes:
      - "${MY_AGENT_CODE:-./my-agent}:/app"
    working_dir: /app
    command: python main.py
    networks:
      sim-shared:
        aliases:
          - "${USER_PREFIX:-dev}-my-agent"   # DNS-имя в общей сети
    depends_on:
      sumo:
        condition: service_healthy
```

Три правила при добавлении сервиса:

1. **Имя контейнера** — всегда `"${USER_PREFIX:-dev}-<name>"`, иначе конфликт с другими пользователями.
2. **Сеть** — подключить к `sim-shared` с алиасом — иначе сервис невидим для остальных.
3. **Зависимости** — `depends_on` с `condition: service_healthy` для SUMO, если сервис использует TraCI.

### 6.2 Создать отдельный сервис в новой директории

```
docker/
└── my-service/
    ├── Dockerfile
    ├── docker-compose.yml
    └── entrypoint.sh          # опционально
```

Минимальный шаблон `docker/my-service/docker-compose.yml`:

```yaml
name: my-service-standalone

services:
  my-service:
    build:
      context: .
      dockerfile: Dockerfile
    image: "traffic-sim/my-service:latest"
    container_name: "${USER_PREFIX:-dev}-my-service"
    hostname: "${USER_PREFIX:-dev}-my-service"
    restart: unless-stopped
    environment:
      SUMO_HOST: "${USER_PREFIX:-dev}-sumo"
    networks:
      sim-shared:
        aliases:
          - "${USER_PREFIX:-dev}-my-service"

networks:
  sim-shared:
    external: true       # ← обязательно: подключаемся к уже существующей сети
    name: sim-shared
```

Запустить:

```bash
docker compose --env-file user-template/.env -f docker/my-service/docker-compose.yml up -d
```

### 6.3 Подключить сервис другого репозитория

Если сервис живёт в отдельном GitLab-репозитории, клонируйте его и укажите путь к Dockerfile:

```yaml
my-external-service:
  build:
    context: /home/korolenkoelizaveta/other-repo   # абсолютный путь или относительный от docker-compose.yml
    dockerfile: Dockerfile
  container_name: "${USER_PREFIX:-dev}-external"
  networks:
    sim-shared:
      aliases:
        - "${USER_PREFIX:-dev}-external"
```

---

## 7. Устранение типичных проблем

| Симптом | Причина | Решение |
|---|---|---|
| `network sim-shared not found` | Инфра-сеть не создана | `make network-up` |
| Конфликт портов при `up` | Другой пользователь занял порт | Изменить `STREAM_HOST_PORT`/`TRACI_HOST_PORT` в `.env` |
| `<user>-sumo` не пингуется из другого контейнера | Контейнер не подключён к `sim-shared` | Проверить секцию `networks:` в compose и перезапустить |
| WeBots не открывается в браузере | Контейнер ещё стартует | Подождать 30 с, проверить `make logs` |
| MATSim OutOfMemoryError | Мало heap | Увеличить `MATSIM_HEAP` в `.env` (не выше `MATSIM_MEM_LIMIT`) |
