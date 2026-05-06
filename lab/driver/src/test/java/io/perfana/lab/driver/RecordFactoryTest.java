package io.perfana.lab.driver;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Random;

import static org.junit.jupiter.api.Assertions.*;

class RecordFactoryTest {

    private RecordFactory factory(double errorRate) throws IOException {
        Path tmp = Files.createTempFile("urls", ".txt");
        Files.writeString(tmp, "/api/foo/:id\n2.0 /api/bar\n");
        Random rnd = new Random(42);
        UrlPatternLoader loader = new UrlPatternLoader(tmp, rnd);
        var errCodes = WeightedPicker.parse("500:30,502:15,503:15,504:15,408:15,429:10", Integer::parseInt, rnd);
        var bodySizes = WeightedPicker.parse("500:80,5000:15,50000:5", Integer::parseInt, rnd);
        return new RecordFactory(loader, rnd, errorRate, true, errCodes, bodySizes,
            List.of("samplerA", "samplerB"), List.of("txnA", "txnB"));
    }

    @Test
    void requestRawHasAllRequiredFields() throws IOException {
        var f = factory(0.01);
        var r = f.requestRaw("trid", "sut-a", "lab", "scen-1", "drv-1");
        assertNotNull(r.getTime());
        assertEquals("trid", r.getTestRunId());
        assertEquals("sut-a", r.getSystemUnderTest());
        assertTrue(r.getResponseTime() >= 5 && r.getResponseTime() <= 5000);
        assertNotNull(r.getUrlHash());
        assertEquals(32, r.getUrlHash().length(), "MD5 hex is 32 chars");
        assertTrue(r.isSuccess());
        assertEquals("200", r.getResponseCode());
    }

    @Test
    void errorRateIsApproximate() throws IOException {
        var f = factory(0.10);
        int errs = 0;
        for (int i = 0; i < 10_000; i++) if (f.isError()) errs++;
        assertTrue(errs > 850 && errs < 1150, "errs=" + errs);
    }

    @Test
    void errorRecordCarriesResponseDataWhenEnabled() throws IOException {
        var f = factory(1.0);
        var e = f.requestError("trid", "sut-a", "lab", "scen-1", "drv-1", "drv-1");
        assertNotNull(e.getResponseData());
        int len = e.getResponseData().length();
        assertTrue(len == 500 || len == 5000 || len == 50_000, "unexpected length=" + len);
        assertNotNull(e.getRequestHeaders());
        assertNotNull(e.getResponseHeaders());
    }

    @Test
    void transactionResponseTimeIsFourSamplersSummed() throws IOException {
        var f = factory(0.0);
        var t = f.transaction("trid", "sut-a", "lab", "scen-1", "drv-1");
        // Lognormal μ=4.4 σ=0.5 sums of 4 — bounded [20, 20000]
        assertTrue(t.getResponseTime() >= 20 && t.getResponseTime() <= 20_000);
    }

    @Test
    void virtualUsersHasActiveThreads() throws IOException {
        var f = factory(0.0);
        var v = f.virtualUsers("trid", "sut-a", "lab", "scen-1", "drv-1", "drv-1", 25);
        assertEquals(25, v.getActiveThreads());
        assertEquals(25, v.getStartedThreads());
        assertEquals(0, v.getFinishedThreads());
    }
}
