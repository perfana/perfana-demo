FROM eclipse-temurin:17-jre-jammy

# TARGETARCH is automatically set by Docker buildx (amd64 or arm64)
ARG TARGETARCH
ARG JMETER_VERSION=5.6.3
ARG PERFANA_CLI_VERSION=0.7.1
ARG TIMESCALEDB_PLUGIN_VERSION=1.0.0

ENV JMETER_HOME=/opt/jmeter
ENV PATH=${JMETER_HOME}/bin:${PATH}

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates curl jq && \
    rm -rf /var/lib/apt/lists/*

# Install JMeter — try dlcdn (Apache CDN, fast) first, fall back to archive (always present, slow)
RUN set -eux; \
    for url in \
        "https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz" \
        "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"; \
    do \
        if wget --tries=2 --timeout=60 -O apache-jmeter-${JMETER_VERSION}.tgz "$url"; then break; fi; \
    done && \
    tar -xzf apache-jmeter-${JMETER_VERSION}.tgz -C /opt && \
    mv /opt/apache-jmeter-${JMETER_VERSION} ${JMETER_HOME} && \
    rm apache-jmeter-${JMETER_VERSION}.tgz

# Install TimescaleDB backend listener plugin and its runtime dependencies from Maven Central
RUN wget -q https://repo1.maven.org/maven2/io/perfana/perfana-jmeter-timescaledb/${TIMESCALEDB_PLUGIN_VERSION}/perfana-jmeter-timescaledb-${TIMESCALEDB_PLUGIN_VERSION}.jar \
    -O ${JMETER_HOME}/lib/ext/perfana-jmeter-timescaledb-${TIMESCALEDB_PLUGIN_VERSION}.jar && \
    wget -q https://repo1.maven.org/maven2/com/zaxxer/HikariCP/5.1.0/HikariCP-5.1.0.jar \
    -O ${JMETER_HOME}/lib/HikariCP-5.1.0.jar && \
    wget -q https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar \
    -O ${JMETER_HOME}/lib/postgresql-42.7.4.jar

# Install perfana-cli (multi-arch: linux_amd64 or linux_arm64)
RUN wget -q https://github.com/perfana/perfana-cli/releases/download/v${PERFANA_CLI_VERSION}/perfana-cli_${PERFANA_CLI_VERSION}_linux_${TARGETARCH}.tar.gz \
    -O /tmp/perfana-cli.tar.gz && \
    tar -xzf /tmp/perfana-cli.tar.gz -C /usr/local/bin perfana-cli && \
    rm /tmp/perfana-cli.tar.gz

WORKDIR /tests

# Stay alive for docker compose exec workflows (perfana-cli run start is called externally)
CMD ["sleep", "infinity"]
