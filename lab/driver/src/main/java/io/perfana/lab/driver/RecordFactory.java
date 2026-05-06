package io.perfana.lab.driver;

import io.perfana.jmeter.timescaledb.model.RequestErrorRecord;
import io.perfana.jmeter.timescaledb.model.RequestRawRecord;
import io.perfana.jmeter.timescaledb.model.TransactionRecord;
import io.perfana.jmeter.timescaledb.model.UrlPatternRecord;
import io.perfana.jmeter.timescaledb.model.VirtualUsersRecord;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Random;

/**
 * Synthesises JMeter-shaped records with realistic distributions.
 * Uses the production model classes' Builder pattern (matches what the
 * production listener does) so wire path is identical.
 */
public final class RecordFactory {
    private final UrlPatternLoader urls;
    private final Random random;
    private final double errorRate;
    private final boolean saveResponseBody;
    private final WeightedPicker<Integer> errorCodes;
    private final WeightedPicker<Integer> responseBodySizes;
    private final List<String> samplerPool;
    private final List<String> transactionPool;

    public RecordFactory(UrlPatternLoader urls,
                         Random random,
                         double errorRate,
                         boolean saveResponseBody,
                         WeightedPicker<Integer> errorCodes,
                         WeightedPicker<Integer> responseBodySizes,
                         List<String> samplerPool,
                         List<String> transactionPool) {
        this.urls = urls;
        this.random = random;
        this.errorRate = errorRate;
        this.saveResponseBody = saveResponseBody;
        this.errorCodes = errorCodes;
        this.responseBodySizes = responseBodySizes;
        this.samplerPool = samplerPool;
        this.transactionPool = transactionPool;
    }

    public boolean isError() { return random.nextDouble() < errorRate; }

    public RequestRawRecord requestRaw(String testRunId, String sut, String env,
                                       String scenario, String location) {
        int rt = lognormalInt(4.4, 0.5, 5, 5000);
        int connect = Math.min(rt, uniform(1, 50));
        int latency = Math.max(0, rt - connect - uniform(1, 10));
        String url = urls.nextUrl();

        return RequestRawRecord.builder()
            .time(Instant.now())
            .testRunId(testRunId)
            .systemUnderTest(sut)
            .testEnvironment(env)
            .scenarioName(scenario)
            .location(location)
            .transactionName(samplePool(transactionPool))
            .samplerName(samplePool(samplerPool))
            .success(true)
            .requestSize(uniform(200, 2000))
            .responseSize(lognormalInt(8.0, 1.0, 200, 200_000))
            .responseCode("200")
            .responseConnectTime(connect)
            .responseLatency(latency)
            .responseTime(rt)
            .urlHash(md5(url))
            .build();
    }

    public RequestErrorRecord requestError(String testRunId, String sut, String env,
                                           String scenario, String location, String node) {
        int code = errorCodes.pick();
        int rt = lognormalInt(5.5, 0.5, 5, 30_000);
        int connect = Math.min(rt, uniform(1, 100));
        String url = urls.nextUrl();

        RequestErrorRecord.Builder b = RequestErrorRecord.builder()
            .time(Instant.now())
            .testRunId(testRunId)
            .systemUnderTest(sut)
            .testEnvironment(env)
            .scenarioName(scenario)
            .location(location)
            .nodeName(node)
            .transactionName(samplePool(transactionPool))
            .samplerName(samplePool(samplerPool))
            .responseCode(Integer.toString(code))
            .responseTime(rt)
            .connectionTime(connect)
            .url(url)
            .urlHash(md5(url))
            .responseMessage("synthetic-error-" + code)
            .randomId(random.nextInt());

        if (saveResponseBody) {
            int sz = responseBodySizes.pick();
            b.responseData(syntheticBody(sz))
             .requestHeaders("Host: lab\r\nContent-Type: application/json\r\n")
             .responseHeaders("Server: synthetic\r\nContent-Length: " + sz + "\r\n");
        }
        return b.build();
    }

    public TransactionRecord transaction(String testRunId, String sut, String env,
                                         String scenario, String location) {
        // Transaction rt = sum of ~4 sampler rts
        int rt = 0;
        for (int i = 0; i < 4; i++) rt += lognormalInt(4.4, 0.5, 5, 5000);
        return TransactionRecord.builder()
            .time(Instant.now())
            .testRunId(testRunId)
            .systemUnderTest(sut)
            .testEnvironment(env)
            .scenarioName(scenario)
            .location(location)
            .transactionName(samplePool(transactionPool))
            .success(!isError())
            .requestSize(uniform(800, 8000))
            .responseSize(lognormalInt(9.0, 1.0, 800, 800_000))
            .responseTime(rt)
            .build();
    }

    public VirtualUsersRecord virtualUsers(String testRunId, String sut, String env,
                                           String scenario, String location, String node,
                                           int active) {
        return VirtualUsersRecord.builder()
            .time(Instant.now())
            .testRunId(testRunId)
            .systemUnderTest(sut)
            .testEnvironment(env)
            .scenarioName(scenario)
            .location(location)
            .nodeName(node)
            .activeThreads(active)
            .startedThreads(active)
            .finishedThreads(0)
            .build();
    }

    public UrlPatternRecord urlPattern(String urlHash, String sut, String env,
                                       String normalizedUrl, String originalExample) {
        return UrlPatternRecord.builder()
            .urlHash(urlHash)
            .systemUnderTest(sut)
            .testEnvironment(env)
            .normalizedUrl(normalizedUrl)
            .originalExample(originalExample)
            .firstSeen(Instant.now())
            .build();
    }

    private int uniform(int lo, int hi) {
        return lo + random.nextInt(Math.max(1, hi - lo));
    }

    private int lognormalInt(double mu, double sigma, int min, int max) {
        double v = Math.exp(mu + sigma * random.nextGaussian());
        if (v < min) v = min;
        if (v > max) v = max;
        return (int) v;
    }

    private String samplePool(List<String> pool) {
        return pool.get(random.nextInt(pool.size()));
    }

    private String syntheticBody(int size) {
        StringBuilder sb = new StringBuilder(size);
        String pad = "{\"error\":\"synthetic\",\"detail\":\"lorem ipsum dolor sit amet\"}";
        while (sb.length() < size) sb.append(pad);
        sb.setLength(size);
        return sb.toString();
    }

    private static String md5(String s) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            return HexFormat.of().formatHex(md.digest(s.getBytes()));
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }
}
