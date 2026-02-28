FROM maven:3.9-eclipse-temurin-17

# Install JMeter and x2i
RUN apt-get update && \
    apt-get install -y wget curl && \
    rm -rf /var/lib/apt/lists/*

# Install JMeter
ENV JMETER_VERSION=5.6.3
ENV JMETER_HOME=/opt/apache-jmeter-${JMETER_VERSION}
ENV PATH=${JMETER_HOME}/bin:${PATH}

RUN wget https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz && \
    tar -xzf apache-jmeter-${JMETER_VERSION}.tgz -C /opt && \
    rm apache-jmeter-${JMETER_VERSION}.tgz

# Install x2i (X-to-InfluxDB tool from Perfana)
RUN wget https://github.com/perfana/x2i/releases/download/x2i-1.0.0/x2i-linux-amd64 -O /usr/bin/x2i && \
    chmod +x /usr/bin/x2i

# Install custom JMeter plugins to local Maven repo
COPY plugins/breakingit-jmeter-influxdb-1.0.0.jar /tmp/
COPY plugins/breakingit-jmeter-timescaledb-1.0.0.jar /tmp/
COPY plugins/events-jmeter-maven-plugin-3.8.0-events-3-SNAPSHOT.jar /tmp/
RUN mvn install:install-file \
    -Dfile=/tmp/breakingit-jmeter-influxdb-1.0.0.jar \
    -DgroupId=io.breakingit \
    -DartifactId=jmeter-influxdb \
    -Dversion=1.0.0 \
    -Dpackaging=jar && \
    mvn install:install-file \
    -Dfile=/tmp/breakingit-jmeter-timescaledb-1.0.0.jar \
    -DgroupId=io.breakingit \
    -DartifactId=jmeter-timescaledb \
    -Dversion=1.0.0 \
    -Dpackaging=jar && \
    mvn install:install-file \
    -Dfile=/tmp/events-jmeter-maven-plugin-3.8.0-events-3-SNAPSHOT.jar \
    -DgroupId=io.perfana \
    -DartifactId=events-jmeter-maven-plugin \
    -Dversion=3.8.0-events-3-SNAPSHOT \
    -Dpackaging=jar && \
    rm /tmp/breakingit-jmeter-influxdb-1.0.0.jar /tmp/breakingit-jmeter-timescaledb-1.0.0.jar /tmp/events-jmeter-maven-plugin-3.8.0-events-3-SNAPSHOT.jar

# Set working directory
WORKDIR /tests

# Keep container running
CMD ["tail", "-f", "/dev/null"]
