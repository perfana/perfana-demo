# JMeter Afterburner Performance Tests

This directory contains JMeter-based performance tests for the Afterburner application with Perfana integration.

## Project Structure

```
jmeter/
├── pom.xml                          # Maven configuration with JMeter plugin
├── src/test/jmeter/                 # JMeter test plans (.jmx files)
│   └── afterburner-test-plan.jmx   # Main test plan
└── README.md                        # This file
```

## Prerequisites

### Using Docker (Recommended)
- Docker and Docker Compose
- Running Afterburner environment (see root README)

### Running Locally
- Maven 3.6+
- Java 11+
- JMeter 5.6.3
- x2i tool (for InfluxDB integration)

## Running Tests

### Using Docker (Recommended)

The easiest way to run JMeter tests is using the provided Docker container:

**Build the JMeter container:**
```bash
docker-compose build jmetertest
```

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
docker-compose up -d jmetertest

# Run tests
docker-compose exec jmetertest mvn clean verify

# Run with custom profile
docker-compose exec jmetertest mvn clean verify -Ptest-type-stress

# Run with custom parameters
docker-compose exec jmetertest mvn clean verify \
  -DtargetThreads=20 \
  -DdurationInSeconds=180
```

### Running Locally

If you have Maven and JMeter installed locally:

```bash
cd jmeter
mvn clean verify
```

### Test Profiles

Different test types are available as Maven profiles:

**Load Test (default):**
```bash
mvn clean verify -Ptest-type-load
```
- 10 concurrent users
- 60 second ramp-up
- 300 second (5 min) duration

**Stress Test:**
```bash
mvn clean verify -Ptest-type-stress
```
- 50 concurrent users
- 120 second ramp-up
- 600 second (10 min) duration

**Endurance Test:**
```bash
mvn clean verify -Ptest-type-endurance
```
- 20 concurrent users
- 300 second ramp-up
- 3600 second (1 hour) duration

**Spike Test:**
```bash
mvn clean verify -Ptest-type-spike
```
- 100 concurrent users
- 10 second ramp-up
- 180 second (3 min) duration

### Custom Configuration

Override properties via command line:

```bash
mvn clean verify \
  -DtargetThreads=20 \
  -DrampupTimeInSeconds=30 \
  -DdurationInSeconds=180 \
  -DtargetHost=localhost \
  -DtargetPort=8090
```

### Disable Perfana Integration

Run tests without sending results to Perfana:

```bash
mvn clean verify -DperfanaEnabled=false
```

### Debug Mode

Enable debug logging:

```bash
mvn clean verify -Ddebug=true
```

## Test Configuration

### Key Properties

| Property | Default | Description |
|----------|---------|-------------|
| `targetHost` | `afterburner-fe` | Target application host |
| `targetPort` | `8080` | Target application port |
| `targetProtocol` | `http` | Protocol (http/https) |
| `targetThreads` | `10` | Number of concurrent users |
| `rampupTimeInSeconds` | `60` | Time to reach target threads |
| `durationInSeconds` | `300` | Test duration in seconds |
| `perfanaEnabled` | `true` | Enable Perfana integration |
| `perfanaUrl` | `http://host.docker.internal:3001` | Perfana API URL |

### Perfana Integration

The tests are configured to:
- Send test results to Perfana for analysis
- Collect Spring Boot actuator metrics
- Track Git commit information
- Send JMeter results to InfluxDB
- Enable automated performance assertions

## Viewing Results

### JMeter Reports

After test execution, reports are generated in:
- `target/jmeter/reports/` - HTML reports
- `target/jmeter/results/` - Raw JTL files

### Perfana Dashboard

If Perfana is enabled, view results at:
- Local: http://localhost:4000
- Demo environment: https://demo.perfana.cloud

### Grafana Dashboards

View real-time metrics at:
- http://localhost:3000 (login: perfana/perfana)

## Test Plan Details

The `afterburner-test-plan.jmx` includes the following endpoints:

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

### Disabled by Default
- `GET /memory/grow` - Memory leak simulation (can cause issues)

## Troubleshooting

### Connection Refused

Ensure the Afterburner application is running:
```bash
docker compose ps afterburner-fe
```

### Perfana Connection Issues

If Perfana is not needed, disable it:
```bash
mvn clean verify -DperfanaEnabled=false
```

Or check Perfana API is accessible:
```bash
curl http://localhost:3001/health
```

### High Error Rate

Check the application logs:
```bash
docker compose logs afterburner-fe
```

## Advanced Usage

### Custom Test Plans

Add new JMeter test plans to `src/test/jmeter/`:
1. Create or export a `.jmx` file
2. Place it in `src/test/jmeter/`
3. Maven will automatically execute all `.jmx` files in that directory

### Environment Variables

Set environment variables for dynamic configuration:

```bash
export SUT_VERSION="1.2.3"
export GIT_SHA=$(git rev-parse HEAD)
mvn clean verify
```

### Running from Docker

If using the loadtest container:

```bash
docker compose exec loadtest sh -c "cd /tests/jmeter && mvn clean verify"
```

## Integration with CI/CD

Example GitHub Actions / Jenkins usage:

```bash
# Set version and metadata
export SUT_VERSION=${BUILD_NUMBER}
export GIT_SHA=${GIT_COMMIT}
export buildResultsUrl=${BUILD_URL}

# Run tests with specific profile
cd jmeter
mvn clean verify -Ptest-type-load

# Check exit code for pass/fail
if [ $? -eq 0 ]; then
  echo "Performance tests passed!"
else
  echo "Performance tests failed!"
  exit 1
fi
```

## Contributing

When adding new tests:
1. Use descriptive names for samplers
2. Add response assertions where appropriate
3. Set reasonable timeouts
4. Document any special configuration needed
5. Test locally before committing

## Resources

- [JMeter Documentation](https://jmeter.apache.org/)
- [Perfana Documentation](https://perfana.io/docs)
- [events-jmeter-maven-plugin](https://github.com/perfana/perfana-java-client)
- [Afterburner GitHub](https://github.com/perfana/afterburner)
