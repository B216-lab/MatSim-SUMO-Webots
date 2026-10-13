FROM ubuntu:24.04

ARG SUMO_VERSION=1.27.1
LABEL maintainer="traffic-sim" \
      sumo.version="${SUMO_VERSION}"

ENV SUMO_HOME=/usr/share/sumo \
    DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1

# SUMO stable PPA гарантирует актуальную версию (1.27.x) на Ubuntu 24.04.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates \
    && add-apt-repository ppa:sumo/stable \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        sumo \
        sumo-tools \
        # GUI/display deps
        xvfb \
        fluxbox \
        x11vnc \
        novnc \
        libgl1 libgl1-mesa-dri libglu1-mesa \
        libxcb-xinerama0 libxkbcommon-x11-0 \
        libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-shape0 \
        libxi6 libxtst6 libdbus-1-3 \
        # ffmpeg for CI SUMO-GUI MP4 recording (x11grab)
        ffmpeg \
        python3 \
        python3-pip \
    && pip3 install --break-system-packages traci sumolib \
    && apt-get purge -y software-properties-common \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /scenarios

# Дефолтный сценарий хранится в /opt/sumo-defaults/ — вне точки монтирования
# /scenarios/, которую перекрывает volume. Entrypoint копирует файлы при старте
# если конфиг не найден в /scenarios/.
RUN mkdir -p /opt/sumo-defaults && \
printf '<configuration>\n  <input><net-file value="default.net.xml"/></input>\n  <time><end value="86400"/></time>\n</configuration>\n' \
    > /opt/sumo-defaults/default.sumocfg && \
printf '<net version="1.16" junctionCornerDetail="5" limitTurnSpeed="5.50"><location netOffset="0.00,0.00" convBoundary="0.00,0.00,100.00,0.00" origBoundary="-180.00,-90.00,180.00,90.00" projParameter="!"/><edge id="e1" from="n1" to="n2" priority="1"><lane id="e1_0" index="0" speed="13.89" length="100.00" shape="0.00,-1.60 100.00,-1.60"/></edge><junction id="n1" type="dead_end" x="0.00" y="0.00" incLanes="" intLanes="" shape="0.00,0.00 0.00,-3.20"/><junction id="n2" type="dead_end" x="100.00" y="0.00" incLanes="e1_0" intLanes="" shape="100.00,-3.20 100.00,0.00"/></net>\n' \
    > /opt/sumo-defaults/default.net.xml

# TraCI-порт и noVNC порт
EXPOSE 8813 6080

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
