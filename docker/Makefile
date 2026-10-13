# =============================================================================
# Makefile для управления симуляционной платформой
#
# Каждый пользователь запускает make из своей копии репозитория:
#   cd ~/citytraffic/docker
#   make up        ← поднять свой стек
#   make down      ← остановить
#   make logs      ← логи
#
# Администратор дополнительно может управлять всеми стеками через admin-* цели.
# =============================================================================

SHELL := /bin/bash
.PHONY: help \
        network-up network-down network-status \
        build build-sumo build-matsim build-webots \
        up down logs restart \
        sumo-gui sumo-netedit sumo-server \
        admin-init-envs admin-up-all admin-down-all \
        status ps clean

TEMPLATE := user-template/docker-compose.yml
ENV_FILE  := user-template/.env

SIM_NETWORK        := sim-shared
SIM_NETWORK_SUBNET := 172.20.0.0/16
SIM_NETWORK_GW     := 172.20.0.1

# Читаем USER_PREFIX из .env для использования в целях (логи, статус)
_USER_PREFIX := $(shell grep -E '^USER_PREFIX=' $(ENV_FILE) 2>/dev/null | cut -d= -f2)

help: ## Показать список доступных команд
	@echo ""
	@echo "Симуляционная платформа: MATSim + SUMO + WeBots"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'
	@echo ""

# -----------------------------------------------------------------------------
# Проверка: .env заполнен корректно
# -----------------------------------------------------------------------------
_check-env:
	@if [ ! -f $(ENV_FILE) ]; then \
		cp user-template/.env.example $(ENV_FILE); \
		echo "Created $(ENV_FILE) from template. Edit USER_PREFIX and ports, then re-run."; \
		exit 1; \
	fi
	@grep -q '^USER_PREFIX=changeme' $(ENV_FILE) && \
		(echo "ERROR: Set USER_PREFIX in $(ENV_FILE) — value 'changeme' is a placeholder" && exit 1) || true
	@grep -qE '^USER_PREFIX=\S+' $(ENV_FILE) || \
		(echo "ERROR: USER_PREFIX is empty in $(ENV_FILE)" && exit 1)

# -----------------------------------------------------------------------------
# Инфраструктура (один раз на сервере — выполняет администратор)
# -----------------------------------------------------------------------------

network-up: ## Создать общую сеть sim-shared (один раз на сервере)
	@echo "Creating shared network $(SIM_NETWORK)..."
	@docker network inspect $(SIM_NETWORK) > /dev/null 2>&1 \
		&& echo "Network $(SIM_NETWORK) already exists, skipping" \
		|| docker network create \
			--driver bridge \
			--subnet $(SIM_NETWORK_SUBNET) \
			--gateway $(SIM_NETWORK_GW) \
			--label project=traffic-sim \
			--label managed-by=sim-infrastructure \
			$(SIM_NETWORK)
	@echo "Network $(SIM_NETWORK) is ready"

network-down: ## Удалить общую сеть (только при полном сносе)
	@echo "Removing shared network $(SIM_NETWORK)..."
	docker network rm $(SIM_NETWORK)

network-status: ## Показать состояние сети sim-shared и подключённые контейнеры
	@docker network inspect $(SIM_NETWORK) --format \
		'Network: {{.Name}} | Driver: {{.Driver}} | Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}'
	@echo ""
	@echo "Connected containers:"
	@docker network inspect $(SIM_NETWORK) --format \
		'{{range .Containers}}  - {{.Name}} ({{.IPv4Address}}){{"\n"}}{{end}}'

# -----------------------------------------------------------------------------
# Сборка образов (один раз после клонирования репозитория)
# -----------------------------------------------------------------------------

build: build-sumo build-matsim build-webots ## Собрать все образы

build-sumo: ## Собрать образ SUMO
	docker compose -f sumo/docker-compose.yml build

build-matsim: ## Собрать образ MATSim
	docker compose -f matsim/docker-compose.yml build

build-webots: ## Собрать образ WeBots
	docker compose -f webots/docker-compose.yml build

# -----------------------------------------------------------------------------
# Пользовательский стек (каждый запускает из своего ~/citytraffic/docker/)
# -----------------------------------------------------------------------------

up: _check-env ## Поднять свой стек (SUMO traci-server + WeBots)
	docker compose --env-file $(ENV_FILE) -f $(TEMPLATE) up -d sumo webots
	@echo "Stack '$(_USER_PREFIX)' started"
	@echo "WeBots streaming -> http://<tailscale-ip>:$(shell grep -E '^STREAM_HOST_PORT=' $(ENV_FILE) | cut -d= -f2)"

down: _check-env ## Остановить свой стек
	docker compose --env-file $(ENV_FILE) -f $(TEMPLATE) down
	@echo "Stack '$(_USER_PREFIX)' stopped"

logs: _check-env ## Логи своего стека (follow, Ctrl+C для выхода)
	docker compose --env-file $(ENV_FILE) -f $(TEMPLATE) logs -f

restart: down up ## Перезапустить свой стек

sumo-gui: _check-env ## Переключить SUMO в режим GUI (noVNC)
	SUMO_MODE=gui docker compose --env-file $(ENV_FILE) -f $(TEMPLATE) \
		up -d --force-recreate sumo
	@echo "SUMO GUI -> http://<tailscale-ip>:$(shell grep -E '^SUMO_NOVNC_HOST_PORT=' $(ENV_FILE) | cut -d= -f2)/vnc.html"

sumo-netedit: _check-env ## Переключить SUMO в режим netedit (noVNC)
	SUMO_MODE=netedit docker compose --env-file $(ENV_FILE) -f $(TEMPLATE) \
		up -d --force-recreate sumo
	@echo "SUMO netedit -> http://<tailscale-ip>:$(shell grep -E '^SUMO_NOVNC_HOST_PORT=' $(ENV_FILE) | cut -d= -f2)/vnc.html"

sumo-server: _check-env ## Вернуть SUMO в режим TraCI-сервера
	docker compose --env-file $(ENV_FILE) -f $(TEMPLATE) \
		up -d --force-recreate sumo
	@echo "SUMO TraCI server started"

# -----------------------------------------------------------------------------
# Административные цели (запускает ubuntu с ubuntu@webots-vm)
# Требуют, чтобы у каждого пользователя был настроен ~/citytraffic/docker/user-template/.env
# -----------------------------------------------------------------------------

admin-init-envs: ## (admin) Проставить USER_PREFIX и порты в .env каждого пользователя
	@for ENTRY in \
		"korolenkoelizaveta:1234:8813:8080:6083:6080" \
		"ruslanmuhamed123:1235:8814:8081:6084:6081" \
		"kravectrofim:1236:8815:8082:6085:6082" \
		"ubuntu:1237:8816:8083:6086:6090"; do \
		USER=$$(echo $$ENTRY         | cut -d: -f1); \
		STREAM=$$(echo $$ENTRY       | cut -d: -f2); \
		TRACI=$$(echo $$ENTRY        | cut -d: -f3); \
		VIEWER=$$(echo $$ENTRY       | cut -d: -f4); \
		SUMO_NOVNC=$$(echo $$ENTRY   | cut -d: -f5); \
		NOVNC=$$(echo $$ENTRY        | cut -d: -f6); \
		ENV="/home/$$USER/citytraffic/docker/user-template/.env"; \
		if sudo -u "$$USER" test -f "$$ENV" 2>/dev/null; then \
			sudo -u "$$USER" sed -i "s/^USER_PREFIX=.*/USER_PREFIX=$$USER/" "$$ENV"; \
			sudo -u "$$USER" sed -i "s/^STREAM_HOST_PORT=.*/STREAM_HOST_PORT=$$STREAM/" "$$ENV"; \
			sudo -u "$$USER" sed -i "s/^TRACI_HOST_PORT=.*/TRACI_HOST_PORT=$$TRACI/" "$$ENV"; \
			sudo -u "$$USER" sed -i "s/^VIEWER_HOST_PORT=.*/VIEWER_HOST_PORT=$$VIEWER/" "$$ENV"; \
			sudo -u "$$USER" sed -i "s/^SUMO_NOVNC_HOST_PORT=.*/SUMO_NOVNC_HOST_PORT=$$SUMO_NOVNC/" "$$ENV"; \
			sudo -u "$$USER" sed -i "s/^NOVNC_HOST_PORT=.*/NOVNC_HOST_PORT=$$NOVNC/" "$$ENV"; \
			echo "$$USER: STREAM=$$STREAM TRACI=$$TRACI VIEWER=$$VIEWER SUMO_NOVNC=$$SUMO_NOVNC NOVNC=$$NOVNC"; \
		else \
			echo "Skipping $$USER: $$ENV not found"; \
		fi; \
	done

admin-up-all: ## (admin) Поднять стеки для всех пользователей
	@for USER in korolenkoelizaveta ruslanmuhamed123 kravectrofim ubuntu; do \
		DIR="/home/$$USER/citytraffic/docker"; \
		if sudo -u "$$USER" test -f "$$DIR/user-template/.env" 2>/dev/null; then \
			echo "Starting stack for $$USER..."; \
			sudo -u "$$USER" bash -c \
				"cd $$DIR && docker compose --env-file user-template/.env -f $(TEMPLATE) up -d --force-recreate sumo webots"; \
		else \
			echo "Skipping $$USER: $$DIR/user-template/.env not found"; \
		fi; \
	done

admin-down-all: ## (admin) Остановить стеки всех пользователей
	@for USER in korolenkoelizaveta ruslanmuhamed123 kravectrofim ubuntu; do \
		DIR="/home/$$USER/citytraffic/docker"; \
		if sudo -u "$$USER" test -f "$$DIR/user-template/.env" 2>/dev/null; then \
			echo "Stopping stack for $$USER..."; \
			sudo -u "$$USER" bash -c \
				"cd $$DIR && docker compose --env-file user-template/.env -f $(TEMPLATE) down"; \
		fi; \
	done

# -----------------------------------------------------------------------------
# Статус и очистка
# -----------------------------------------------------------------------------

status: ## Показать все запущенные контейнеры симуляции
	@echo "Running simulation containers:"
	@docker ps --filter "network=$(SIM_NETWORK)" \
		--format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

ps: status ## Алиас для status

clean: ## Удалить остановленные контейнеры и неиспользуемые тома симуляции
	@echo "Cleaning up stopped containers and dangling volumes..."
	docker container prune -f --filter "label=project=traffic-sim"
	docker volume prune -f --filter "label=project=traffic-sim"
