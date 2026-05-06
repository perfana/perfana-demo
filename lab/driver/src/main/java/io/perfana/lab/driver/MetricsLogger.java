package io.perfana.lab.driver;

import com.zaxxer.hikari.HikariDataSource;
import io.perfana.jmeter.timescaledb.writer.TimescaleDBWriter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.lang.reflect.Field;
import java.time.Instant;
import java.util.Collection;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Emits a single CSV line every 10s to stdout — captured by `docker logs`
 * and aggregated by run-soak.sh into driver_metrics.csv.
 *
 * Format:
 *   METRICS,timestamp,driver,sut,scenario,rps_target,rps_actual,
 *   hikari_active,hikari_idle,hikari_waiting,
 *   buffer_total,buffer_request_raw,buffer_transactions,buffer_errors,
 *   buffer_vusers,buffer_url_patterns,under_pressure
 *
 * The writer doesn't expose flush success/fail counters, so this logger
 * uses isUnderPressure() as a proxy: a tick where under_pressure=1
 * indicates buffered records were re-added (backpressure event).
 */
public final class MetricsLogger {
    private static final Logger log = LoggerFactory.getLogger(MetricsLogger.class);
    private final ScheduledExecutorService exec = Executors.newSingleThreadScheduledExecutor();
    private final TimescaleDBWriter writer;
    private final SamplePump pump;
    private final DriverConfig config;
    private long lastSamples = 0;
    private long lastTimestamp = System.nanoTime();

    public MetricsLogger(TimescaleDBWriter writer, SamplePump pump, DriverConfig config) {
        this.writer = writer;
        this.pump = pump;
        this.config = config;
    }

    public void start() {
        System.out.println("METRICS_HEADER,timestamp,driver,sut,scenario,rps_target,rps_actual,"
            + "hikari_active,hikari_idle,hikari_waiting,"
            + "buffer_total,buffer_request_raw,buffer_transactions,buffer_errors,"
            + "buffer_vusers,buffer_url_patterns,under_pressure");
        exec.scheduleAtFixedRate(this::tick, 10, 10, TimeUnit.SECONDS);
    }

    public void stop() {
        exec.shutdownNow();
    }

    private void tick() {
        try {
            long nowNs = System.nanoTime();
            long samples = pump.samplesEmitted();
            double seconds = (nowNs - lastTimestamp) / 1e9;
            double rpsActual = (samples - lastSamples) / Math.max(seconds, 0.001);
            lastSamples = samples;
            lastTimestamp = nowNs;

            HikariSnapshot h = readHikari();
            BufferSnapshot b = readBuffers();
            int underPressure = writer.isUnderPressure() ? 1 : 0;

            System.out.printf("METRICS,%s,%s,%s,%s,%d,%.1f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d%n",
                Instant.now(),
                config.node,
                config.sut,
                config.scenario,
                config.rps,
                rpsActual,
                h.active, h.idle, h.waiting,
                b.total, b.requestRaw, b.transactions, b.errors, b.vusers, b.urlPatterns,
                underPressure);
        } catch (Throwable t) {
            log.warn("Metrics tick failed: {}", t.getMessage());
        }
    }

    private HikariSnapshot readHikari() {
        try {
            Field dsField = TimescaleDBWriter.class.getDeclaredField("dataSource");
            dsField.setAccessible(true);
            HikariDataSource ds = (HikariDataSource) dsField.get(writer);
            var mxBean = ds.getHikariPoolMXBean();
            return new HikariSnapshot(
                mxBean.getActiveConnections(),
                mxBean.getIdleConnections(),
                mxBean.getThreadsAwaitingConnection());
        } catch (Throwable t) {
            return new HikariSnapshot(-1, -1, -1);
        }
    }

    private BufferSnapshot readBuffers() {
        BufferSnapshot s = new BufferSnapshot();
        s.requestRaw = bufferSize("requestRawBuffer");
        s.transactions = bufferSize("transactionBuffer");
        s.errors = bufferSize("requestErrorBuffer");
        s.vusers = bufferSize("virtualUsersBuffer");
        s.urlPatterns = bufferSize("urlPatternBuffer");
        s.total = writer.getTotalBufferSize();
        return s;
    }

    private int bufferSize(String fieldName) {
        try {
            Field f = TimescaleDBWriter.class.getDeclaredField(fieldName);
            f.setAccessible(true);
            Object v = f.get(writer);
            if (v instanceof Collection<?> c) {
                synchronized (c) {
                    return c.size();
                }
            }
            return -1;
        } catch (Throwable t) {
            return -1;
        }
    }

    record HikariSnapshot(int active, int idle, int waiting) {}

    static class BufferSnapshot {
        int total;
        int requestRaw, transactions, errors, vusers, urlPatterns;
    }
}
