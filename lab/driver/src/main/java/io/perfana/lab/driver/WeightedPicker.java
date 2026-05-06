package io.perfana.lab.driver;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

public final class WeightedPicker<T> {
    private final List<T> values = new ArrayList<>();
    private final List<Double> weights = new ArrayList<>();
    private final double total;
    private final Random random;

    public WeightedPicker(List<T> values, List<Double> weights, Random random) {
        if (values.size() != weights.size() || values.isEmpty()) {
            throw new IllegalArgumentException("values and weights must be same non-empty size");
        }
        this.values.addAll(values);
        this.weights.addAll(weights);
        double sum = 0;
        for (double w : weights) sum += w;
        this.total = sum;
        this.random = random;
    }

    public T pick() {
        double r = random.nextDouble() * total;
        double acc = 0;
        for (int i = 0; i < values.size(); i++) {
            acc += weights.get(i);
            if (r < acc) return values.get(i);
        }
        return values.get(values.size() - 1);
    }

    public static <T> WeightedPicker<T> parse(String spec, java.util.function.Function<String, T> keyParser, Random random) {
        List<T> keys = new ArrayList<>();
        List<Double> weights = new ArrayList<>();
        for (String pair : spec.split(",")) {
            String[] kv = pair.trim().split(":");
            if (kv.length != 2) throw new IllegalArgumentException("Bad pair: " + pair);
            keys.add(keyParser.apply(kv[0].trim()));
            weights.add(Double.parseDouble(kv[1].trim()));
        }
        return new WeightedPicker<>(keys, weights, random);
    }
}
