package io.perfana.lab.driver;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Loads URL patterns from a file, parses optional weights, substitutes :param
 * placeholders deterministically so url_hash is stable across drivers.
 *
 * File format (one URL per line):
 *   /api/foo/:id
 *   1.5 /api/bar/:userId/orders/:orderId
 *   # comments and blank lines ignored
 */
public final class UrlPatternLoader {
    private static final Pattern PARAM = Pattern.compile(":([a-zA-Z][a-zA-Z0-9_]*)");
    private static final Pattern LINE  = Pattern.compile("^(?:([0-9]+(?:\\.[0-9]+)?)\\s+)?(\\S.*)$");

    private final List<String> templates = new ArrayList<>();
    private final List<Double> weights = new ArrayList<>();
    private double totalWeight = 0.0;
    private final Random random;

    public UrlPatternLoader(Path file, Random random) throws IOException {
        this.random = random;
        if (!Files.exists(file)) {
            throw new IOException("URL patterns file not found: " + file
                + " — operator must supply this file (see lab/driver/url-patterns.txt.example).");
        }
        for (String raw : Files.readAllLines(file)) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            Matcher m = LINE.matcher(line);
            if (!m.matches()) throw new IOException("Cannot parse URL line: " + raw);
            double w = m.group(1) == null ? 1.0 : Double.parseDouble(m.group(1));
            templates.add(m.group(2));
            weights.add(w);
            totalWeight += w;
        }
        if (templates.isEmpty()) throw new IOException("URL patterns file is empty: " + file);
    }

    public int size() { return templates.size(); }

    /**
     * One generated URL paired with the template it came from. The substituted
     * URL is what becomes the requests_raw.url_hash; the template is what the
     * UI shows in the Top-10 URLs list (so all `/api/foo/1023`, `/api/foo/1041`
     * group under `/api/foo/:id`).
     */
    public record Selection(String template, String url) {}

    public Selection nextSelection() {
        double r = random.nextDouble() * totalWeight;
        double acc = 0;
        for (int i = 0; i < templates.size(); i++) {
            acc += weights.get(i);
            if (r < acc) {
                String tpl = templates.get(i);
                return new Selection(tpl, substitute(tpl));
            }
        }
        String tpl = templates.get(templates.size() - 1);
        return new Selection(tpl, substitute(tpl));
    }

    public String nextUrl() {
        return nextSelection().url();
    }

    private String substitute(String template) {
        Matcher m = PARAM.matcher(template);
        StringBuilder out = new StringBuilder();
        while (m.find()) {
            m.appendReplacement(out, Matcher.quoteReplacement(paramValue(m.group(1))));
        }
        m.appendTail(out);
        return out.toString();
    }

    private String paramValue(String param) {
        int n = (Math.abs(param.hashCode()) + random.nextInt(50)) % 50;
        return switch (param) {
            case "id", "orderId", "productId", "customerId", "userId" -> Integer.toString(1000 + n);
            case "uuid" -> String.format("%08x-%04x-%04x-%04x-%012x", n, n & 0xffff, n & 0xffff, n & 0xffff, (long) n * 1000L);
            default -> "v" + n;
        };
    }
}
