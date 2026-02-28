# Perfana Next-Gen Docker Compose Setup

## Overview

This docker-compose configuration includes:
- **PostgreSQL** (TimescaleDB) - Unified database for both Perfana and Keycloak
- **Keycloak** - Authentication server sharing the same PostgreSQL instance
- **Perfana Web** - Next.js frontend (ARM64 optimized)
- **Perfana API** - NestJS backend (ARM64 optimized)
- Supporting services (Redis, Grafana, Prometheus, etc.)

## Architecture

### Database Setup
- Single PostgreSQL instance with two databases:
  - `perfana_native` - Main Perfana application database (auto-initialized with schema)
  - `keycloak` - Keycloak authentication database
- TimescaleDB extension enabled for time-series data
- Shared credentials via environment variables
- Automatic schema initialization on first startup:
  1. Creates `keycloak` database
  2. Loads complete Perfana schema into `perfana_native`

### Authentication Flow
1. Keycloak manages user authentication
2. Frontend uses Keycloak JS adapter for SSO
3. Backend validates JWT tokens from Keycloak
4. API keys supported for programmatic access

## Prerequisites

- Docker Desktop for Mac (with M1 support)
- Docker Compose v2+
- 8GB+ RAM available for Docker
- Built Docker images:
  - `perfana/perfana-web:latest`
  - `perfana/perfana-api:latest`

## Quick Start

### 1. Build the Images

```bash
cd /Users/daniel/workspace/perfana-next-gen
./build-m1.sh
```

### 2. Set Environment Variables

Create a `.env` file in the perfana-demo directory:

```bash
# Database
POSTGRES_PASSWORD=your_secure_password

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin_password
KEYCLOAK_CLIENT_SECRET=your_client_secret
```

### 3. Start Services

```bash
cd /Users/daniel/workspace/perfana-demo

# Start postgres and keycloak first
docker compose -f docker-compose-next-gen.yml up -d postgres keycloak

# Wait for services to be healthy (30-60 seconds)
docker compose -f docker-compose-next-gen.yml ps

# Start perfana services
docker compose -f docker-compose-next-gen.yml up -d perfana-web perfana-api

# Start all other services
docker compose -f docker-compose-next-gen.yml up -d
```

## Service URLs

| Service | URL | Description |
|---------|-----|-------------|
| Perfana Web | http://localhost:4002 | Next.js frontend |
| Perfana API | http://localhost:3001 | NestJS backend API |
| Keycloak | http://localhost:8080 | Authentication admin console |
| PostgreSQL | localhost:5432 | Database server |
| Grafana | http://localhost:3000 | Observability dashboards |
| Prometheus | http://localhost:9090 | Metrics storage |

## Keycloak Configuration

### Automatic Realm Provisioning

The Perfana realm is **automatically imported** on first startup from `keycloak/realms/perfana-realm.json`.

**Includes:**
- ✅ Pre-configured `perfana` realm
- ✅ Two clients: `perfana-web` (public) and `perfana-api` (confidential)
- ✅ Three roles: `user`, `admin`, `perfana-admin`
- ✅ Two test users (see below)
- ✅ Security policies and token lifespans

### Default Users

**Administrator:**
- Username: `admin`
- Password: `admin`
- Roles: admin, perfana-admin, user
- Email: admin@perfana.io

**Test User:**
- Username: `testuser`
- Password: `test123`
- Roles: user
- Email: test@perfana.io

⚠️ **Change these passwords in production!**

### Accessing Keycloak Admin Console

```bash
# URL: http://localhost:8080
# Login with admin credentials
```

### Getting API Client Secret

1. Access Keycloak Admin Console at http://localhost:8080
2. Select "perfana" realm
3. Go to Clients → perfana-api
4. Go to Credentials tab
5. Copy the client secret
6. Add to your `.env` file:
```bash
KEYCLOAK_CLIENT_SECRET=your-secret-here
```

### Creating Additional Users

1. Keycloak Admin Console → Users → Add User
2. Set username and email
3. Go to Credentials tab → Set password
4. Go to Role Mappings tab → Assign roles
5. User can now login to Perfana

## Database Management

### Database Initialization

On first startup, PostgreSQL automatically runs initialization scripts from `database/init/`:

1. **01-create-keycloak-db.sql** - Creates keycloak database
2. **02-init-perfana-schema.sh** - Shell script that loads the Perfana schema
3. **03-perfana-schema.sql** - Complete Perfana database schema (190KB)

These scripts only run once when the postgres volume is first created. To re-initialize:
```bash
# Stop and remove volumes
docker compose -f docker-compose-next-gen.yml down -v

# Start fresh (will re-run init scripts)
docker compose -f docker-compose-next-gen.yml up -d postgres
```

### Connect to PostgreSQL

```bash
# Using docker exec
docker exec -it perfana-postgres psql -U perfana -d perfana_native

# Using psql client
psql -h localhost -p 5432 -U perfana -d perfana_native
```

### View Databases

```sql
-- List all databases
\l

-- Connect to keycloak database
\c keycloak

-- List tables
\dt
```

### Backup Database

```bash
# Backup perfana database
docker exec perfana-postgres pg_dump -U perfana perfana_native > perfana_backup.sql

# Backup keycloak database
docker exec perfana-postgres pg_dump -U perfana keycloak > keycloak_backup.sql
```

## Troubleshooting

### Check Service Health

```bash
# View all container status
docker compose -f docker-compose-next-gen.yml ps

# Check logs for specific service
docker compose -f docker-compose-next-gen.yml logs -f perfana-api
docker compose -f docker-compose-next-gen.yml logs -f keycloak
docker compose -f docker-compose-next-gen.yml logs -f postgres
```

### Common Issues

#### Keycloak fails to start
- **Cause**: Keycloak database not created
- **Solution**: Check postgres logs and verify init script ran
```bash
docker compose -f docker-compose-next-gen.yml logs postgres
```

#### API cannot connect to database
- **Cause**: Environment variables not set correctly
- **Solution**: Verify `.env` file and restart API
```bash
docker compose -f docker-compose-next-gen.yml restart perfana-api
```

#### Web app shows authentication errors
- **Cause**: Keycloak not configured or realm/clients missing
- **Solution**: Complete Keycloak configuration steps above

### Reset Everything

```bash
# Stop all services
docker compose -f docker-compose-next-gen.yml down

# Remove volumes (WARNING: deletes all data)
docker compose -f docker-compose-next-gen.yml down -v

# Start fresh
docker compose -f docker-compose-next-gen.yml up -d
```

## Development

### Accessing Container Shells

```bash
# Postgres
docker exec -it perfana-postgres bash

# Keycloak
docker exec -it perfana-keycloak bash

# API
docker exec -it perfana-api bash
```

### View Real-time Logs

```bash
# All services
docker compose -f docker-compose-next-gen.yml logs -f

# Specific service
docker compose -f docker-compose-next-gen.yml logs -f perfana-api
```

## Performance Optimization

### ARM64 Architecture
All critical services are built for ARM64 (M1/M2 Macs) for optimal performance:
- perfana-web: Native ARM64 build
- perfana-api: Native ARM64 build
- postgres: ARM64 compatible TimescaleDB
- keycloak: ARM64 compatible

### Resource Limits
Adjust resources in docker-compose file as needed:

```yaml
services:
  perfana-api:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2048M
```

## Security Notes

1. **Change default passwords** in production
2. **Use HTTPS** with proper certificates
3. **Enable SSL** for PostgreSQL connections
4. **Restrict CORS origins** to specific domains
5. **Use secrets management** for sensitive data
6. **Enable Keycloak HTTPS** in production

## Monitoring

Monitor service health:

```bash
# Check health status
docker compose -f docker-compose-next-gen.yml ps

# View resource usage
docker stats
```

Access monitoring tools:
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

## Next Steps

1. Configure Keycloak realm and clients
2. Create initial users in Keycloak
3. Run database migrations (if any)
4. Configure Grafana dashboards
5. Set up Prometheus alerts
6. Test authentication flow

## Support

For issues:
1. Check logs: `docker compose -f docker-compose-next-gen.yml logs`
2. Verify network: `docker network inspect perfana-demo_perfana`
3. Check health: `docker compose -f docker-compose-next-gen.yml ps`
