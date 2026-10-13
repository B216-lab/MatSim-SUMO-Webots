FROM eclipse-temurin:17-jre-jammy

ARG MATSIM_VERSION=15.0
LABEL maintainer="traffic-sim" \
      matsim.version="${MATSIM_VERSION}"

ENV MATSIM_VERSION=${MATSIM_VERSION} \
    MATSIM_HOME=/matsim \
    DEBIAN_FRONTEND=noninteractive

WORKDIR /matsim

# Official release zip includes jar + libs/ (Maven artifact alone is not runnable).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        wget ca-certificates unzip python3 \
    && wget -q \
        "https://github.com/matsim-org/matsim-libs/releases/download/${MATSIM_VERSION}/matsim-${MATSIM_VERSION}-release.zip" \
        -O /tmp/matsim.zip \
    && unzip -q /tmp/matsim.zip -d /tmp \
    && mv /tmp/matsim-${MATSIM_VERSION}/matsim-${MATSIM_VERSION}.jar /matsim/matsim.jar \
    && mv /tmp/matsim-${MATSIM_VERSION}/libs /matsim/libs \
    && rm -rf /tmp/matsim.zip /tmp/matsim-${MATSIM_VERSION} \
    && apt-get purge -y wget unzip \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

VOLUME ["/matsim/input", "/matsim/output"]

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
