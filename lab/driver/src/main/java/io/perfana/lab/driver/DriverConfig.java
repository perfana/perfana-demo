package io.perfana.lab.driver;

/** Plain config record — fully populated by SyntheticDriver from CLI/env. */
public final class DriverConfig {
    public final String pgbouncerHost;
    public final int pgbouncerPort;
    public final String dbUser;
    public final String dbPassword;
    public final String dbName;
    public final long rps;
    public final String duration;
    public final String sut;
    public final String env;
    public final String scenario;
    public final String location;
    public final String node;
    public final String testRunId;
    public final int batchSize;
    public final int flushIntervalSeconds;
    public final int hikariMaxPoolSize;
    public final double errorRate;
    public final boolean saveResponseBody;
    public final String urlPatternsPath;
    public final String errorCodeMix;
    public final String responseBodySizeMix;

    public DriverConfig(
        String pgbouncerHost, int pgbouncerPort, String dbUser, String dbPassword, String dbName,
        long rps, String duration, String sut, String env, String scenario, String location, String node,
        String testRunId, int batchSize, int flushIntervalSeconds, int hikariMaxPoolSize,
        double errorRate, boolean saveResponseBody, String urlPatternsPath,
        String errorCodeMix, String responseBodySizeMix) {
        this.pgbouncerHost = pgbouncerHost;
        this.pgbouncerPort = pgbouncerPort;
        this.dbUser = dbUser;
        this.dbPassword = dbPassword;
        this.dbName = dbName;
        this.rps = rps;
        this.duration = duration;
        this.sut = sut;
        this.env = env;
        this.scenario = scenario;
        this.location = location;
        this.node = node;
        this.testRunId = testRunId;
        this.batchSize = batchSize;
        this.flushIntervalSeconds = flushIntervalSeconds;
        this.hikariMaxPoolSize = hikariMaxPoolSize;
        this.errorRate = errorRate;
        this.saveResponseBody = saveResponseBody;
        this.urlPatternsPath = urlPatternsPath;
        this.errorCodeMix = errorCodeMix;
        this.responseBodySizeMix = responseBodySizeMix;
    }
}
