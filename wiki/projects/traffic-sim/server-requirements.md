# Настройка сервера webots-vm

> Выполняется один раз администратором (`ubuntu@webots-vm`).  
> Порядок важен.

---

## 0. Предварительные условия

- Ubuntu 24.04 LTS
- Tailscale установлен, сервер виден в сети (`tailscale status`)
- Репозиторий `citytraffic` склонирован в `~/citytraffic`

---

## 1. Docker Engine

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu
newgrp docker
docker --version   # проверить
```

---

## 2. Пользователи в группе docker

Каждый пользователь должен быть в группе `docker` чтобы запускать `docker compose` без sudo.

```bash
for u in korolenkoelizaveta ruslanmuhamed123 kravectrofim ubuntu; do
    sudo usermod -aG docker $u
done
```

Пользователям нужно перелогиниться чтобы группа применилась:

```bash
# На каждой сессии пользователя, или попросить переподключиться:
newgrp docker
```

---

## 3. Репозиторий у каждого пользователя

Каждый пользователь клонирует репозиторий в свою домашнюю директорию.  
Администратор может сделать это за них:

```bash
for u in korolenkoelizaveta ruslanmuhamed123 kravectrofim; do
    sudo -u $u bash -c "
        git clone https://gitlab.<org>.com/citytraffic-lab/citytraffic.git /home/$u/citytraffic
    "
done
# ubuntu уже имеет ~/citytraffic
```

---

## 4. Docker сеть

Создаётся один раз. Все пользовательские контейнеры подключаются к ней.

```bash
cd ~/citytraffic/docker
make network-up
```

---

## 5. Сборка образов

```bash
cd ~/citytraffic/docker
make build
# Собирает: traffic-sim/sumo:1.27.1, traffic-sim/matsim:15.0, traffic-sim/webots:R2023b
# Занимает ~10-15 минут при первом запуске (WeBots скачивает ~400MB .deb)
```

---

## 6. Инициализация окружений и запуск стеков

```bash
cd ~/citytraffic/docker

# Прописывает USER_PREFIX и уникальные порты в .env каждого пользователя
make admin-init-envs

# Поднимает SUMO + WeBots для всех 4 пользователей
make admin-up-all

# Проверить
make status
```

Распределение портов после `admin-init-envs`:

| Пользователь | WeBots stream | SUMO TraCI | WeBots viewer | SUMO noVNC |
|---|---|---|---|---|
| korolenkoelizaveta | 1234 | 8813 | 8080 | 6083 |
| ruslanmuhamed123 | 1235 | 8814 | 8081 | 6084 |
| kravectrofim | 1236 | 8815 | 8082 | 6085 |
| ubuntu | 1237 | 8816 | 8083 | 6086 |

---

## 7. GitLab Runner

### Установка

```bash
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install -y gitlab-runner
sudo usermod -aG docker gitlab-runner
```

### Регистрация

Получить токен: GitLab → репозиторий `city-traffic-model` → Settings → CI/CD → Runners → New project runner.

```bash
sudo gitlab-runner register \
  --url https://gitlab.<org>.com \
  --token <registration-token> \
  --executor docker \
  --docker-image docker:latest \
  --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
  --description "webots-vm" \
  --tag-list "webots-vm" \
  --run-untagged false \
  --locked false
```

Флаг `--docker-volumes /var/run/docker.sock:/var/run/docker.sock` — позволяет CI jobs запускать `docker run` из контейнера runner (Docker-in-Docker через socket).

### Проверка

```bash
sudo gitlab-runner status
sudo gitlab-runner list
# Runner должен быть "alive"
```

---

## 8. Проверка всего стека

```bash
# Контейнеры запущены
make -C ~/citytraffic/docker status

# Сеть создана и контейнеры в ней
make -C ~/citytraffic/docker network-status

# SUMO TraCI доступен (пример для korolenkoelizaveta)
docker exec korolenkoelizaveta-sumo grep -q ':226D' /proc/net/tcp && echo "SUMO OK"

# WeBots streaming доступен
docker exec korolenkoelizaveta-webots grep -q ':04D2' /proc/net/tcp6 && echo "WeBots OK"

# Runner активен
sudo gitlab-runner verify
```

---

## 9. Лимит загрузки CI-артефактов (HTTP 413)

MP4 из `karla-marksa:visualize` (~1.5 MB за 300 с) падают на **Uploading artifacts** с `413 Request Entity Too Large`, если на **сервере GitLab** (`ilab-irk.ru`) nginx оставлен с дефолтным `client_max_body_size` **1 m**.

Это настраивается **на хосте GitLab**, не на webots-vm. Сокращать длительность записи не нужно.

Инструкция и скрипт:

- `wiki/projects/traffic-sim/gitlab-artifact-upload-limits.md`
- `scripts/gitlab/fix-artifact-upload-413.sh` (запуск на GitLab-сервере от root)
- `scripts/gitlab/probe-artifact-upload-limit.sh` (проверка с webots-vm)

---

## 10. Повторный запуск после перезагрузки сервера

```bash
cd ~/citytraffic/docker
make network-up     # сеть не переживает перезагрузку
make admin-up-all   # поднять стеки
```

Чтобы автоматизировать после перезагрузки — добавить в cron или systemd:

```bash
# /etc/rc.local или systemd service
cd /home/ubuntu/citytraffic/docker && make network-up && make admin-up-all
```
