FROM eclipse-temurin:21-jre-jammy

# TARGETARCH is automatically set by Docker buildx (amd64 or arm64)
ARG TARGETARCH
ARG BREAKTEST_VERSION=2026.07.03
ARG PERFANA_CLI_VERSION=0.7.4
ARG TIMESCALEDB_PLUGIN_VERSION=1.0.4

ENV JMETER_HOME=/opt/breaktest
ENV PATH=${JMETER_HOME}/bin:${PATH}

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates curl jq && \
    rm -rf /var/lib/apt/lists/*

# Install BreakTest (JMeter-compatible fork) from its GitHub release
RUN set -eux; \
    wget --tries=3 --timeout=60 -O breaktest-${BREAKTEST_VERSION}.tgz \
        "https://github.com/Breaking-IT/breaktest/releases/download/rel/v${BREAKTEST_VERSION}/breaktest-${BREAKTEST_VERSION}.tgz" && \
    tar -xzf breaktest-${BREAKTEST_VERSION}.tgz -C /opt && \
    mv /opt/breaktest-${BREAKTEST_VERSION} ${JMETER_HOME} && \
    rm breaktest-${BREAKTEST_VERSION}.tgz

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
