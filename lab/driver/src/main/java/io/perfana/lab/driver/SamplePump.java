package io.perfana.lab.driver;

import io.perfana.jmeter.timescaledb.model.UrlPatternRecord;
import io.perfana.jmeter.timescaledb.writer.TimescaleDBWriter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Token-bucket-paced loop that emits samples to TimescaleDBWriter at a
 * target rps. One thread per driver is sufficient at 1500 rps.
 *
 * For each "request" emission, also emits a transaction every 4 requests
 * (matches a JMeter transaction controller wrapping 4 samplers) and a
 * virtual_users sample every 5s.
 */
public final class SamplePump implements Runnable {
    private static final Logger log = LoggerFactory.getLogger(SamplePump.class);

    private final TimescaleDBWriter writer;
    private final RecordFactory factory;
    private final DriverConfig config;
    private final AtomicLong samplesEmitted = new AtomicLong();

    public SamplePump(TimescaleDBWriter writer, RecordFactory factory, DriverConfig config) {
        this.writer = writer;
        this.factory = factory;
        this.config = config;
    }

    public long samplesEmitted() { return samplesEmitted.get(); }

    @Override
    public void run() {
        long rps = config.rps;
        long nanosPerSample = 1_000_000_000L / rps;
        long start = System.nanoTime();
        long deadline = start + Duration.parse(config.duration).toNanos();
        long nextEmit = start;
        long virtualUsersNextEmit = start;

        log.info("SamplePump start: rps={}, duration={}, sut={}, scenario={}",
            rps, config.duration, config.sut, config.scenario);

        long requestCount = 0;
        Instant testStart = Instant.now();
        while (System.nanoTime() < deadline) {
            long now = System.nanoTime();
            if (now < nextEmit) {
                long wait = nextEmit - now;
                if (wait > 1_000_000) {
                    try {
                        Thread.sleep(wait / 1_000_000);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        return;
                    }
                }
                continue;
            }

            // Emit one request (raw or error).
            if (factory.isError()) {
                writer.writeRequestError(factory.requestError(
                    config.testRunId, config.sut, config.env, config.scenario,
                    config.location, config.node));
            } else {
                writer.writeRequestRaw(factory.requestRaw(
                    config.testRunId, config.sut, config.env, config.scenario, config.location));
            }
            // Drain any newly-discovered URL patterns. Bounded by the number
            // of distinct (template × substituted) combinations the driver has
            // generated so far; rate falls off as the population stabilises.
            UrlPatternRecord up;
            while ((up = factory.pollPendingUrlPattern()) != null) {
                writer.writeUrlPattern(up);
            }
            samplesEmitted.incrementAndGet();
            requestCount++;

            // Emit a transaction every 4 requests
            if (requestCount % 4 == 0) {
                writer.writeTransaction(factory.transaction(
                    config.testRunId, config.sut, config.env, config.scenario, config.location));
            }

            // Emit a virtual_users sample every 5s
            if (now >= virtualUsersNextEmit) {
                int active = computeActiveVUs(testStart);
                writer.writeVirtualUsers(factory.virtualUsers(
                    config.testRunId, config.sut, config.env, config.scenario,
                    config.location, config.node, active));
                virtualUsersNextEmit = now + 5_000_000_000L;
            }

            nextEmit += nanosPerSample;
        }

        log.info("SamplePump done: emitted {} samples", samplesEmitted.get());
    }

    /** Ramp 1→50 over the first 60s, hold 50, then ramp to 0 over the last 60s. */
    private int computeActiveVUs(Instant testStart) {
        long elapsed = Duration.between(testStart, Instant.now()).toSeconds();
        long total = Duration.parse(config.duration).toSeconds();
        if (elapsed < 60) return Math.max(1, (int) (50 * elapsed / 60));
        if (elapsed > total - 60) return Math.max(0, (int) (50 * (total - elapsed) / 60));
        return 50;
    }
}
