# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Perfana demo environment - a comprehensive performance monitoring and testing platform that combines observability tools with automated performance testing capabilities. The project demonstrates how to detect performance regressions using load testing, metrics collection, and machine learning analysis.

## Architecture

### Perfana Stack (PostgreSQL/React/NestJS)
- **perfana-web**: Next.js 15 frontend (port 4000)
- **perfana-api**: NestJS TypeScript API (port 3001)
- **perfana-worker**: BullMQ worker for pipeline processing
- **perfana-grafana-sync**: Grafana dashboard synchronization
- **perfana-report**: PDF report generation service (port 3003)
- **perfana-snapshot**: Grafana snapshot service
- **perfana-migration**: TypeORM database migration runner
- **PostgreSQL**: TimescaleDB database (port 5432)
- **Keycloak**: Authentication server (port 8080)
- **Redis**: Job queue (port 6379)

### Observability & Testing Stack
- **Grafana**: Dashboards and visualization (port 3000)
- **Prometheus**: Metrics collection (port 9090)
- **InfluxDB**: Time-series database (port 8086)
- **Tempo**: Distributed tracing (port 3200)
- **Pyroscope**: Continuous profiling (port 4040)
- **Loki**: Log aggregation (port 3100)
- **Alertmanager**: Alert routing (port 9093)
- **Telegraf**: Docker metrics collection
- **Afterburner**: Spring Boot test applications (fe: 8090, be: internal)
- **Gatling**: Load testing framework (Kotlin-based)
- **JMeter**: Load testing framework (orchestrated by perfana-cli)

## Core Development Commands

### Environment Management
```bash
# Initialize full demo environment (first time)
./init-demo.sh

# Start existing environment (all services)
./start.sh

# Start infrastructure only (for local Perfana development)
./start-infra.sh

# Docker compose directly
docker compose up -d
docker compose down
```

### Load Testing
```bash
# Run baseline performance test (JMeter)
./deploy-and-test-jmeter.sh baseline

# Test with CPU performance issue
./deploy-and-test-jmeter.sh cpu

# Test with connection pool issue
./deploy-and-test-jmeter.sh pool

# Test with backend calls issue
./deploy-and-test-jmeter.sh backend

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
- **jmeter/perfana.yaml**: perfana-cli configuration for JMeter tests
- **jmeter/src/test/jmeter/**: JMeter test plans (.jmx files)

### Docker Orchestration
- **docker-compose.yml**: Full stack configuration
- Environment variables in `.env`

### Service Configuration
- **grafana/**: Dashboard provisioning and configuration
- **prometheus/**: Metrics collection configuration
- **tempo/**: Distributed tracing configuration
- **keycloak/**: Realm configuration and theme
- **database/**: PostgreSQL init scripts and schema

## Key Integration Points

### Perfana API Integration
- JMeter load tests use `perfana-cli` to orchestrate test lifecycle and send results to Perfana
- Gatling load tests use `perfana-java-client` to send results to Perfana
- API key authentication required (generated via /api/key endpoint)
- Test metadata includes: systemUnderTest, version, workload, testEnvironment

### Metrics Flow
1. Applications → Prometheus/InfluxDB → Grafana → Perfana
2. Load test results → Perfana via events-gatling-maven-plugin (Gatling) or perfana-cli (JMeter)
3. Performance analysis via Perfana worker pipeline

### Database
- **PostgreSQL/TimescaleDB**: Perfana data with TypeORM migrations
- **Keycloak DB**: Separate database in same PostgreSQL instance
- **MariaDB**: Sample employee database for Afterburner demo app

## Development Workflow

1. **Environment Setup**: Use `./init-demo.sh` for complete setup
2. **Local Development**: Use `./start-infra.sh` to run infrastructure, then run Perfana services locally
3. **Testing**: Run load tests with `./deploy-and-test-jmeter.sh [type]`
4. **Analysis**: View results in Perfana UI (localhost:4000) and Grafana (localhost:3000)

## Troubleshooting

### Common Issues
- **Port conflicts**: Check exposed ports in docker-compose.yml
- **Database connectivity**: Verify PostgreSQL connection and migrations
- **Load test failures**: Check API key configuration in perfana.yaml (JMeter) or pom.xml (Gatling)
- **Keycloak issues**: Check realm import logs and health endpoint

### Health Checks
- Perfana UI: http://localhost:4000 (admin@perfana.io / Perfana1!)
- Perfana API: http://localhost:3001/api/health
- Keycloak: http://localhost:8080 (admin / admin)
- Grafana: http://localhost:3000 (perfana / perfana)
- Prometheus: http://localhost:9090

## Testing Infrastructure

The project includes automated performance regression detection:
- Baseline tests establish performance benchmarks
- Subsequent tests are compared against baselines
- Performance issues (CPU, memory, connection pools) are automatically detected
- Results integrate with CI/CD pipelines through Perfana API

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **perfana-demo** (570 symbols, 552 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/perfana-demo/context` | Codebase overview, check index freshness |
| `gitnexus://repo/perfana-demo/clusters` | All functional areas |
| `gitnexus://repo/perfana-demo/processes` | All execution flows |
| `gitnexus://repo/perfana-demo/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
