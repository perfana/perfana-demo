package io.perfana.lab.driver;

import io.perfana.jmeter.timescaledb.config.TimescaleDBConfig;
import io.perfana.jmeter.timescaledb.writer.TimescaleDBWriter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import picocli.CommandLine;

import java.lang.reflect.Field;
import java.nio.file.Path;
import java.util.List;
import java.util.Random;
import java.util.concurrent.Callable;

@CommandLine.Command(name = "lab-driver", mixinStandardHelpOptions = true,
    description = "Synthetic JMeter-shaped load driver for the perfana DB stress lab.")
public final class SyntheticDriver implements Callable<Integer> {
    private static final Logger log = LoggerFactory.getLogger(SyntheticDriver.class);

    @CommandLine.Option(names = "--pgbouncer-host",
        defaultValue = "${env:DRIVER_PGBOUNCER_HOST:-pgbouncer}")
    String pgbouncerHost;

    @CommandLine.Option(names = "--pgbouncer-port",
        defaultValue = "${env:DRIVER_PGBOUNCER_PORT:-6432}")
    int pgbouncerPort;

    @CommandLine.Option(names = "--user", defaultValue = "${env:DRIVER_DB_USER:-perfana}")
    String dbUser;

    @CommandLine.Option(names = "--password", defaultValue = "${env:DRIVER_DB_PASSWORD:-perfana}")
    String dbPassword;

    @CommandLine.Option(names = "--db", defaultValue = "${env:DRIVER_DB_NAME:-perfana}")
    String dbName;

    @CommandLine.Option(names = "--rps", defaultValue = "${env:DRIVER_RPS:-1500}")
    long rps;

    @CommandLine.Option(names = "--duration", defaultValue = "${env:DRIVER_DURATION:-PT1H}")
    String duration;

    @CommandLine.Option(names = "--system-under-test",
        defaultValue = "${env:DRIVER_SUT:-lab-sut-a}")
    String sut;

    @CommandLine.Option(names = "--test-environment",
        defaultValue = "${env:DRIVER_ENV:-lab}")
    String env;

    @CommandLine.Option(names = "--scenario-name",
        defaultValue = "${env:DRIVER_SCENARIO:-scenario-1}")
    String scenario;

    @CommandLine.Option(names = "--location",
        defaultValue = "${env:DRIVER_LOCATION:-driver-1}")
    String location;

    @CommandLine.Option(names = "--node-name",
        defaultValue = "${env:DRIVER_NODE:-driver-1}")
    String node;

    @CommandLine.Option(names = "--test-run-id", required = true,
        defaultValue = "${env:DRIVER_TEST_RUN_ID}")
    String testRunId;

    @CommandLine.Option(names = "--batch-size",
        defaultValue = "${env:DRIVER_BATCH_SIZE:-1000}")
    int batchSize;

    @CommandLine.Option(names = "--flush-interval-seconds",
        defaultValue = "${env:DRIVER_FLUSH_INTERVAL_SECONDS:-1}")
    int flushIntervalSeconds;

    @CommandLine.Option(names = "--hikari-max-pool-size",
        defaultValue = "${env:DRIVER_HIKARI_MAX_POOL_SIZE:-10}")
    int hikariMaxPoolSize;

    @CommandLine.Option(names = "--error-rate",
        defaultValue = "${env:DRIVER_ERROR_RATE:-0.01}")
    double errorRate;

    @CommandLine.Option(names = "--save-response-body",
        defaultValue = "${env:DRIVER_SAVE_RESPONSE_BODY:-true}")
    boolean saveResponseBody;

    @CommandLine.Option(names = "--url-patterns",
        defaultValue = "${env:DRIVER_URL_PATTERNS:-/url-patterns.txt}")
    String urlPatternsPath;

    @CommandLine.Option(names = "--error-code-mix",
        defaultValue = "${env:DRIVER_ERROR_CODE_MIX:-500:30,502:15,503:15,504:15,408:15,429:10}")
    String errorCodeMix;

    @CommandLine.Option(names = "--response-body-size-mix",
        defaultValue = "${env:DRIVER_RESPONSE_BODY_SIZE_MIX:-500:80,5000:15,50000:5}")
    String responseBodySizeMix;

    @Override
    public Integer call() throws Exception {
        DriverConfig cfg = new DriverConfig(
            pgbouncerHost, pgbouncerPort, dbUser, dbPassword, dbName,
            rps, duration, sut, env, scenario, location, node,
            testRunId, batchSize, flushIntervalSeconds, hikariMaxPoolSize,
            errorRate, saveResponseBody, urlPatternsPath,
            errorCodeMix, responseBodySizeMix);

        log.info("Driver starting: rps={} sut={} scenario={} testRunId={}",
            cfg.rps, cfg.sut, cfg.scenario, cfg.testRunId);
        log.info("DB target: jdbc:postgresql://{}:{}/{}",
            cfg.pgbouncerHost, cfg.pgbouncerPort, cfg.dbName);

        Random rnd = new Random();
        UrlPatternLoader urls = new UrlPatternLoader(Path.of(cfg.urlPatternsPath), rnd);
        log.info("Loaded {} URL patterns", urls.size());

        var errCodes = WeightedPicker.parse(cfg.errorCodeMix, Integer::parseInt, rnd);
        var bodySizes = WeightedPicker.parse(cfg.responseBodySizeMix, Integer::parseInt, rnd);

        List<String> samplerPool = List.of(
            "GET-" + cfg.scenario, "POST-" + cfg.scenario,
            "PUT-" + cfg.scenario, "DELETE-" + cfg.scenario, "PATCH-" + cfg.scenario);
        List<String> txnPool = List.of(
            "login-" + cfg.scenario, "checkout-" + cfg.scenario,
            "search-" + cfg.scenario, "browse-" + cfg.scenario, "report-" + cfg.scenario);

        RecordFactory factory = new RecordFactory(
            urls, rnd, cfg.errorRate, cfg.saveResponseBody,
            errCodes, bodySizes, samplerPool, txnPool);

        TimescaleDBConfig writerCfg = buildWriterConfig(cfg);
        TimescaleDBWriter writer = new TimescaleDBWriter(writerCfg);

        SamplePump pump = new SamplePump(writer, factory, cfg);
        MetricsLogger metrics = new MetricsLogger(writer, pump, cfg);
        metrics.start();

        Thread pumpThread = new Thread(pump, "sample-pump");
        pumpThread.start();
        pumpThread.join();

        log.info("Pump finished — closing writer (flushes remaining buffers)");
        writer.close();
        metrics.stop();
        return 0;
    }

    /**
     * Build a TimescaleDBConfig without going through JMeter's BackendListenerContext.
     * Uses reflection because TimescaleDBConfig fields are private and there is
     * no public builder/constructor.
     */
    private TimescaleDBConfig buildWriterConfig(DriverConfig cfg) throws Exception {
        TimescaleDBConfig c = new TimescaleDBConfig();
        setField(c, "host", cfg.pgbouncerHost);
        setField(c, "port", cfg.pgbouncerPort);
        setField(c, "database", cfg.dbName);
        setField(c, "schema", "public");
        setField(c, "user", cfg.dbUser);
        setField(c, "password", cfg.dbPassword);
        setField(c, "sslMode", "disable");
        setField(c, "maxPoolSize", cfg.hikariMaxPoolSize);
        setField(c, "connectionTimeout", 30_000);
        setField(c, "batchSize", cfg.batchSize);
        setField(c, "flushInterval", cfg.flushIntervalSeconds);
        setField(c, "runId", cfg.testRunId);
        setField(c, "location", cfg.location);
        setField(c, "nodeName", cfg.node);
        setField(c, "systemUnderTest", cfg.sut);
        setField(c, "testEnvironment", cfg.env);
        setField(c, "syntheticMonitoring", false);
        setField(c, "scenarioName", cfg.scenario);
        setField(c, "saveResponseBody", cfg.saveResponseBody);
        setField(c, "normalizeUrls", true);
        return c;
    }

    private static void setField(Object obj, String name, Object value) throws Exception {
        Field f = obj.getClass().getDeclaredField(name);
        f.setAccessible(true);
        f.set(obj, value);
    }

    public static void main(String[] args) {
        int exit = new CommandLine(new SyntheticDriver()).execute(args);
        System.exit(exit);
    }
}
