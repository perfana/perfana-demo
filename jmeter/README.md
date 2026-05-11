# JMeter Afterburner Performance Tests

This directory contains JMeter-based performance tests for the Afterburner application, orchestrated by [perfana-cli](https://github.com/perfana/perfana-cli).

## Project Structure

```
jmeter/
├── perfana.yaml                     # perfana-cli configuration
├── Dockerfile                       # Container image (JMeter + perfana-cli)
├── src/test/jmeter/                 # JMeter test plans (.jmx files)
│   ├── afterburner-test-plan.jmx    # Main test plan
│   ├── webshop-browse-search.jmx    # Browsing/search simulation
│   ├── webshop-checkout-flow.jmx    # Checkout workflow
│   └── search-product.jmx          # Product search tests
└── README.md                        # This file
```

## Prerequisites

### Using Docker (Recommended)
- Docker and Docker Compose
- Running Afterburner environment (see root README)

### Running Locally
- [perfana-cli](https://github.com/perfana/perfana-cli)
- JMeter 5.6.3

## Running Tests

### Using Docker (Recommended)

The easiest way to run JMeter tests is using the provided Docker container:

**Run tests using the deploy script:**
```bash
# Run baseline test
./deploy-and-test-jmeter.sh baseline

# Run CPU test
./deploy-and-test-jmeter.sh cpu

# Run connection pool test
./deploy-and-test-jmeter.sh pool

# Run backend calls test
./deploy-and-test-jmeter.sh backend
```

**Run tests manually in container:**
```bash
# Start the container
docker compose up -d jmetertest

# Run tests with perfana-cli
docker compose exec \
  -e SUT_VERSION=2.4.3-good-baseline \
  -e GIT_SHA=4e2db5f \
  -e JMETER_TEST="webshop-*.jmx" \
  -e ANNOTATIONS="baseline test" \
  jmetertest perfana-cli run start \
    --config /tests/perfana.yaml \
    --version 2.4.3-good-baseline
```

### Configuration

Test parameters are controlled via environment variables passed to the container:

| Variable | Default | Description |
|----------|---------|-------------|
| `SUT_VERSION` | - | Version of system under test |
| `GIT_SHA` | - | Git commit hash |
| `JMETER_TEST` | `afterburner-test-plan.jmx` | Test file glob pattern |
| `ANNOTATIONS` | - | Test run annotation |
| `TARGET_THREADS` | `10` | Number of concurrent users |
| `RAMPUP_TIME_SECONDS` | `60` | Time to reach target threads |
| `DURATION_SECONDS` | `360` | Total test duration in seconds |

### Perfana Integration

The tests are configured via `perfana.yaml` to:
- Send test lifecycle events to Perfana for analysis
- Collect Spring Boot actuator metrics from Afterburner
- Track Git commit information
- Send JMeter results to TimescaleDB
- Enable automated performance assertions

## Viewing Results

### Perfana Dashboard

View results at:
- Local: http://localhost:4000
- Demo environment: https://demo.perfana.cloud

### Grafana Dashboards

View real-time metrics at:
- http://localhost:3000 (login: perfana/perfana)

## Test Plan Details

The test plans target the following Afterburner endpoints:

### Performance Endpoints
- `GET /delay` - Configurable delay
- `GET /cpu/magic-identity-check` - CPU intensive operations
- `GET /parallel` - Parallel processing test

### Business Logic
- `POST /basket/purchase` - Simulate purchases
- `POST /basket/store` - Store basket data
- `GET /basket/all` - Retrieve all baskets

### System Operations
- `GET /system-info` - System information
- `GET /remote/call` - Remote service calls
- `GET /mind-my-business` - Business processing
- `GET /flaky` - Flaky service (50% failure)

## Troubleshooting

### Connection Refused

Ensure the Afterburner application is running:
```bash
docker compose ps afterburner-fe
```

### Perfana Connection Issues

Check Perfana API is accessible:
```bash
curl http://localhost:3001/health
```

### High Error Rate

Check the application logs:
```bash
docker compose logs afterburner-fe
```

## Resources

- [JMeter Documentation](https://jmeter.apache.org/)
- [perfana-cli Documentation](https://github.com/perfana/perfana-cli)
- [Perfana Documentation](https://perfana.io/docs)
- [Afterburner GitHub](https://github.com/perfana/afterburner)
