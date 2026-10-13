FROM ubuntu:24.04

# WeBots R2023b — последний стабильный релиз с поддержкой headless streaming.
# Для обновления измените оба ARG синхронно:
#   WEBOTS_TAG    → метка GitHub release (R2023b, R2024a, …)
#   WEBOTS_DEB    → имя .deb файла в этом релизе
ARG WEBOTS_TAG=R2023b
ARG WEBOTS_DEB=webots_2023b_amd64.deb
LABEL maintainer="traffic-sim" \
      webots.version="${WEBOTS_TAG}"

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    WEBOTS_HOME=/usr/local/webots \
    WEBOTS_DISABLE_SAVE_SCREEN_PERSPECTIVE_ON_CLOSE=true \
    # Отключает запрос обновлений при старте
    WEBOTS_DISABLE_UPDATE_CHECK=true

# --- Системные зависимости ---
# SUMO must match traffic-sim/sumo (PPA 1.27.x). Ubuntu apt ships 1.18, which rejects
# newer net vClasses (container, scooter, …) and never opens TraCI → empty MP4s.
ARG SUMO_VERSION=1.27.1
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates wget \
        software-properties-common \
        # Виртуальный фреймбуфер (headless rendering)
        xvfb \
        # Mesa software OpenGL (CPU рендеринг без GPU)
        libgl1 libgl1-mesa-dri libglu1-mesa libgles2 \
        # WeBots runtime deps
        libglib2.0-0 libdbus-1-3 libxcb-xinerama0 \
        libxkbcommon-x11-0 libxcb-icccm4 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
        libxcb-shape0 libxi6 libxtst6 \
        # noVNC для доступа к GUI через браузер (опционально)
        x11vnc novnc websockify \
        # Python для контроллеров
        python3 python3-pip \
        # ffmpeg for WEBOTS_RECORD_MP4 (x11grab of Xvfb)
        ffmpeg \
    && add-apt-repository -y ppa:sumo/stable \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        sumo \
        sumo-tools \
    && apt-get purge -y software-properties-common \
    && rm -rf /var/lib/apt/lists/*

ENV SUMO_HOME=/usr/share/sumo

# --- Установка WeBots ---
RUN wget -q \
        "https://github.com/cyberbotics/webots/releases/download/${WEBOTS_TAG}/${WEBOTS_DEB}" \
        -O /tmp/webots.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/webots.deb \
    && rm /tmp/webots.deb \
    && rm -rf /var/lib/apt/lists/*

# Добавляем webots в PATH
ENV PATH="${WEBOTS_HOME}/bin:${PATH}"

# Минимальный мир по умолчанию — вне /worlds/ чтобы volume mount не скрыл его.
# Entrypoint копирует его в /worlds/ при старте если пользовательский мир не найден.
RUN mkdir -p /opt/webots-defaults && printf '#VRML_SIM R2023b utf8\n\nWorldInfo {\n}\nViewpoint {\n  orientation -0.5773 0.5773 0.5773 2.0944\n  position 0 0 10\n}\nBackground {\n  skyColor [ 0.4 0.7 1 ]\n}\n' \
    > /opt/webots-defaults/default.wbt

WORKDIR /worlds

# WeBots web streaming порт
EXPOSE 1234
# noVNC порт (если включён NOVNC_ENABLED=true)
EXPOSE 6080

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
