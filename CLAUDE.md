# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Perfana demo environment - a comprehensive performance monitoring and testing platform that combines observability tools with automated performance testing capabilities. The project demonstrates how to detect performance regressions using load testing, metrics collection, and machine learning analysis.

## Architecture

### Legacy Stack (MongoDB/Meteor)
- **perfana-fe**: Meteor-based frontend (port 4000)
- **MongoDB replica set**: mongo1/2/3 (ports 27011-27013) with perfana database
- **perfana-ds-api**: Python FastAPI data science service (port 8080) with MongoDB integration

### Next-Gen Stack (PostgreSQL/React/NestJS)
- **perfana-web**: Next.js 15 frontend (port 4000)
- **perfana-api**: NestJS TypeScript API (port 3001)
- **Supabase**: PostgreSQL database with auth and real-time (port 54321)

### Observability & Testing Stack
- **Grafana**: Dashboards and visualization (port 3000)
- **Prometheus**: Metrics collection (port 9090)
- **InfluxDB**: Time-series database (port 8086)
- **Tempo**: Distributed tracing (port 3200)
- **Pyroscope**: Continuous profiling (port 4040)
- **Afterburner**: Spring Boot test applications (fe: 8090, be: internal)
- **Gatling**: Load testing framework (Kotlin-based)

## Core Development Commands

### Environment Management
```bash
# Initialize full demo environment
./init-demo.sh

# Start existing environment
./start.sh

# Deploy next-gen stack
docker-compose -f docker-compose-next-gen.yml up -d

# Stop all services
./stop.sh

# Clean all containers and volumes
./clean.sh
```

### Load Testing
```bash
# Run baseline performance test
./deploy-and-test.sh baseline

# Test with CPU performance issue
./deploy-and-test.sh cpu

# Test with connection pool issue
./deploy-and-test.sh pool

# Run Gatling test directly from loadtest container
docker compose exec loadtest mvn events-gatling:test
```

### Service Management
```bash
# Check service health
docker compose ps

# View service logs
docker compose logs [service-name]

# Restart specific service
docker compose restart [service-name]
```

## Configuration Files

### Load Testing Configuration
- **loadtest/pom.xml**: Maven configuration for Gatling tests with Perfana integration
- **loadtest/src/test/kotlin/**: Kotlin-based Gatling simulation files
- Key properties: `perfanaUrl`, `systemUnderTest`, `apiKey`, load parameters

### Docker Orchestration
- **docker-compose.yml**: Legacy stack configuration
- **docker-compose-next-gen.yml**: Next-gen stack with PostgreSQL
- Environment variables in `.env` and `.env.next-gen`

### Service Configuration
- **grafana/**: Dashboard provisioning and configuration
- **prometheus/**: Metrics collection configuration
- **tempo/**: Distributed tracing configuration

## Key Integration Points

### Perfana API Integration
- Load tests use `perfana-java-client` to send results to Perfana
- API key authentication required (generated via /api/key endpoint)
- Test metadata includes: systemUnderTest, version, workload, testEnvironment

### Metrics Flow
1. Applications → Prometheus/InfluxDB → Grafana → Perfana
2. Load test results → Perfana via events-gatling-maven-plugin
3. Performance analysis via perfana-ds-api machine learning pipeline

### Database Schemas
- **MongoDB**: Legacy collections for test runs, benchmarks, and metrics
- **PostgreSQL**: New normalized schema with migrations in supabase/migrations/

## Development Workflow

1. **Environment Setup**: Use `./init-demo.sh` for complete setup
2. **Code Changes**: Modify services and rebuild Docker images as needed
3. **Testing**: Run load tests with `./deploy-and-test.sh [type]`
4. **Analysis**: View results in Perfana UI (localhost:4000) and Grafana (localhost:3000)
5. **Migration**: Use next-gen deployment for PostgreSQL-based architecture

## Troubleshooting

### Common Issues
- **Service startup delays**: Use `-s` flag with init scripts to increase sleep time
- **Port conflicts**: Check exposed ports in docker-compose files
- **Database connectivity**: Verify MongoDB replica set or PostgreSQL connection
- **Load test failures**: Check API key configuration in pom.xml

### Health Checks
- Perfana UI: http://localhost:4000 (admin@perfana.io / perfana)
- Grafana: http://localhost:3000 (perfana / perfana)
- Prometheus: http://localhost:9090
- API health: curl http://localhost:3001/health (next-gen)

## Testing Infrastructure

The project includes automated performance regression detection:
- Baseline tests establish performance benchmarks
- Subsequent tests are compared against baselines using ML analysis
- Performance issues (CPU, memory, connection pools) are automatically detected
- Results integrate with CI/CD pipelines through Perfana API