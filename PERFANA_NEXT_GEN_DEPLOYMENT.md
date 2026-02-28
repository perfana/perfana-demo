# Perfana Next-Gen Docker Deployment Guide

This guide shows how to deploy the new Perfana Next-Gen architecture (Next.js + NestJS + Supabase) alongside or instead of the legacy MongoDB/Meteor stack.

## Architecture Overview

### New Next-Gen Stack:
- **perfana-web**: Next.js 15 frontend (replaces Meteor frontend)
- **perfana-api**: NestJS TypeScript API (replaces Meteor backend)
- **supabase**: PostgreSQL database with auth and real-time (replaces MongoDB)

### Legacy Stack (kept for transition):
- **perfana-fe-legacy**: Original Meteor frontend
- **mongo1/2/3**: MongoDB replica set
- **perfana-ds-api**: Data science API (updated to support both databases)

## Quick Start

### 1. Build Images
First, build the new Perfana images:
```bash
# In your perfana-next-gen directory
docker build --target web -t perfana-web:latest -f Dockerfile .
docker build --target api -t perfana-api:latest -f Dockerfile .
```

### 2. Set Environment Variables
```bash
# Copy the environment template
cp .env.next-gen .env

# Edit the .env file with your specific configuration
nano .env
```

### 3. Deploy New Stack
```bash
# Deploy the complete next-gen stack
docker-compose -f docker-compose-next-gen.yml up -d

# Or deploy only the new services (without legacy)
docker-compose -f docker-compose-next-gen.yml up -d perfana-web perfana-api supabase
```

### 4. Access Applications
- **New Perfana Frontend**: http://localhost:4000
- **Perfana API**: http://localhost:3001
- **Legacy Perfana** (if enabled): http://localhost:4001
- **Grafana**: http://localhost:3000
- **Supabase Studio**: http://localhost:54321

## Port Mapping

| Service | Port | Description |
|---------|------|-------------|
| perfana-web | 4000 | New Next.js frontend |
| perfana-api | 3001 | New NestJS API |
| perfana-fe-legacy | 4001 | Legacy Meteor frontend |
| perfana-chat | 3002 | AI Chat service |
| supabase | 54321 | Supabase API Gateway |
| grafana | 3000 | Grafana dashboards |
| prometheus | 9090 | Prometheus metrics |
| influxdb | 8086 | InfluxDB time series |

## Deployment Strategies

### Strategy 1: Side-by-Side Migration (Recommended)
Run both old and new systems in parallel:

```bash
# Deploy everything
docker-compose -f docker-compose-next-gen.yml up -d

# Access new system: http://localhost:4000
# Access old system: http://localhost:4001
```

### Strategy 2: New Stack Only
Deploy only the new architecture:

```bash
# Deploy core new services
docker-compose -f docker-compose-next-gen.yml up -d perfana-web perfana-api supabase grafana tempo prometheus

# Skip legacy services by using profiles
docker-compose -f docker-compose-next-gen.yml --profile new-only up -d
```

### Strategy 3: Legacy with New Database
Keep Meteor frontend but use new PostgreSQL database:

```bash
# Deploy Supabase + legacy frontend
docker-compose -f docker-compose-next-gen.yml up -d supabase perfana-fe-legacy grafana
```

## Database Migration

### Initial Setup
The Supabase container will automatically:
1. Create PostgreSQL database
2. Run migrations from `supabase/migrations/`
3. Import seed data from `supabase/seed.sql`

### Migrate Data from MongoDB
Use the data migration tools:
```bash
# Run migration script (when available)
docker-compose exec perfana-api npm run migrate:mongo-to-postgres

# Or manually migrate specific collections
docker-compose exec perfana-api npm run migrate:test-runs
docker-compose exec perfana-api npm run migrate:benchmarks
```

## Configuration

### Environment Variables
Key environment variables in `.env`:

```bash
# Supabase Database
POSTGRES_PASSWORD=perfana123!
SUPABASE_URL=http://supabase:54321
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# JWT Security
JWT_SECRET=your-super-secure-jwt-secret-here

# External APIs (optional)
OPENAI_API_KEY=your-openai-api-key
GITHUB_TOKEN=your-github-token
```

### Volume Mounts
Critical volumes to persist data:
- `supabase-storage:/var/lib/postgresql/data` - PostgreSQL data
- `grafana-storage:/var/lib/grafana` - Grafana dashboards
- `prometheus-storage:/data` - Prometheus metrics
- `mongo1-storage:/data/db` - MongoDB data (legacy)

## Health Checks

### Verify Services
```bash
# Check all service health
docker-compose -f docker-compose-next-gen.yml ps

# Check specific service logs
docker-compose -f docker-compose-next-gen.yml logs perfana-web
docker-compose -f docker-compose-next-gen.yml logs perfana-api

# Test API endpoints
curl http://localhost:3001/health
curl http://localhost:4000/api/health
```

### Database Connectivity
```bash
# Test Supabase connection
curl http://localhost:54321/health

# Test API database connection
curl http://localhost:3001/api/systems-under-test
```

## Security Considerations

### Production Hardening
1. **Change default passwords** in `.env`
2. **Use proper JWT secrets** (32+ characters)
3. **Configure firewall rules** for external access
4. **Enable HTTPS** with reverse proxy (nginx/traefik)
5. **Set up monitoring** and log aggregation

### Network Security
The `perfana` Docker network isolates services. Only expose necessary ports:
- 4000 (Web UI)
- 3001 (API)
- 3000 (Grafana)

## Troubleshooting

### Common Issues

**1. Service won't start**
```bash
# Check logs
docker-compose -f docker-compose-next-gen.yml logs [service-name]

# Check resource usage
docker stats
```

**2. Database connection errors**
```bash
# Verify Supabase is running
docker-compose -f docker-compose-next-gen.yml ps supabase

# Check database connectivity
docker-compose -f docker-compose-next-gen.yml exec supabase pg_isready
```

**3. Port conflicts**
```bash
# Check what's using ports
netstat -tulpn | grep :4000
lsof -i :3001

# Change ports in docker-compose-next-gen.yml if needed
```

### Performance Tuning

**Resource Limits**
```yaml
# Add to service definitions
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 1G
    reservations:
      memory: 512M
```

**Database Optimization**
```bash
# Tune PostgreSQL settings
# Edit supabase/postgresql.conf:
# shared_buffers = 256MB
# max_connections = 100
# work_mem = 4MB
```

## Monitoring & Observability

### Built-in Monitoring
- **Grafana**: http://localhost:3000 (admin/perfana)
- **Prometheus**: http://localhost:9090
- **Jaeger/Tempo**: http://localhost:16686
- **Pyroscope**: http://localhost:4040

### Application Metrics
The new stack includes:
- Health check endpoints
- Prometheus metrics
- Structured logging
- Distributed tracing
- Performance profiling

## Migration Checklist

- [ ] Build new Docker images
- [ ] Configure environment variables
- [ ] Deploy Supabase database
- [ ] Run database migrations
- [ ] Deploy perfana-api service
- [ ] Deploy perfana-web frontend
- [ ] Test API connectivity
- [ ] Test web interface
- [ ] Migrate historical data
- [ ] Update load test configurations
- [ ] Train users on new interface
- [ ] Decommission legacy services

## Support

### Documentation
- **API Documentation**: http://localhost:3001/api/docs
- **Frontend Guide**: See `apps/web/README.md`
- **Backend Guide**: See `apps/api/README.md`

### Getting Help
1. Check service logs first
2. Verify environment configuration
3. Test individual service endpoints
4. Check database connectivity
5. Review Docker Compose service dependencies

---

This deployment supports both migration strategies and production-ready scalability. The new architecture provides better performance, security, and maintainability compared to the legacy MongoDB/Meteor stack.