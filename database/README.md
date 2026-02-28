# Perfana Database Initialization

This directory contains PostgreSQL initialization scripts that run automatically when the database container is first started.

## Initialization Scripts

Scripts in the `init/` directory run in alphabetical order during first startup:

### 01-create-keycloak-db.sql
Creates the `keycloak` database and grants permissions to the perfana user.

```sql
CREATE DATABASE keycloak;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO perfana;
```

### 02-init-perfana-schema.sh
Shell script that loads the complete Perfana schema into the `perfana` database.

### 03-perfana-schema.sql
Complete Perfana database schema dump (190KB) containing:
- All tables for test runs, benchmarks, metrics, dashboards
- Functions for triggers and data processing
- Views for complex queries
- Indexes for performance
- Foreign key constraints

Source: `/Users/daniel/workspace/perfana-next-gen/database/schema/schema_dump.sql`

## Database Structure

### perfana Database

Main application database containing:

**Core Tables:**
- `test_runs` - Test execution records
- `systems_under_test` - Applications being tested
- `benchmarks` - Performance benchmarks and checks
- `check_results` - Performance check results

**Grafana Integration:**
- `grafana_instances` - Grafana server configurations
- `grafana_dashboards` - Dashboard metadata
- `application_dashboards` - Application-specific dashboards

**Data Science:**
- `ds_metrics` - Time-series metrics data
- `ds_adapt_results` - Performance analysis results
- `ds_control_groups` - Control group definitions
- `ds_compare_config` - Comparison configurations

**Configuration:**
- `test_run_config` - Test run configuration key-value pairs
- `expected_config_changes` - Expected configuration changes tracking
- `api_keys` - API authentication keys

### keycloak Database

Keycloak authentication database (managed by Keycloak).

## Usage

### First Time Setup

1. Start PostgreSQL container:
```bash
docker compose -f docker-compose.yml up -d postgres
```

2. Wait for initialization (check logs):
```bash
docker compose -f docker-compose.yml logs -f postgres
```

3. Verify databases:
```bash
docker exec -it perfana-postgres psql -U perfana -c "\l"
```

### Re-initialize Database

To completely reset and re-run initialization scripts:

```bash
# Stop all services
docker compose -f docker-compose.yml down

# Remove postgres volume (WARNING: deletes all data)
docker volume rm perfana-demo_postgres_data

# Start postgres (will re-run init scripts)
docker compose -f docker-compose.yml up -d postgres
```

## Troubleshooting

### Check Initialization Logs

```bash
docker compose -f docker-compose.yml logs postgres | grep -i "init"
```

### Verify Schema Loaded

```bash
# Connect to perfana
docker exec -it perfana-postgres psql -U perfana -d perfana

# List tables
\dt

# Check table count (should be ~40+ tables)
SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';
```

### Common Issues

**Issue:** Schema fails to load
- Check for syntax errors in 03-perfana-schema.sql
- Verify the \restrict line was removed (line 5 in original)

**Issue:** Keycloak database not created
- Check 01-create-keycloak-db.sql ran successfully
- Verify POSTGRES_USER environment variable is set

**Issue:** Permissions errors
- Ensure perfana user has proper grants
- Check POSTGRES_PASSWORD matches across services

## Updating Schema

To update the schema from the source:

```bash
# Copy latest schema dump
cp /Users/daniel/workspace/perfana-next-gen/database/schema/schema_dump.sql ./init/03-perfana-schema.sql

# Remove problematic \restrict line
sed -i '' '5d' ./init/03-perfana-schema.sql

# Re-initialize database (see Re-initialize Database section)
```

## Security Notes

1. **Production:** Change default passwords in `.env` file
2. **Backups:** Regular backups recommended before schema updates
3. **Access:** Restrict database access to trusted networks
4. **Encryption:** Consider enabling SSL for PostgreSQL connections

## References

- [PostgreSQL Docker Init Scripts](https://hub.docker.com/_/postgres) - Section "Initialization scripts"
- [TimescaleDB Documentation](https://docs.timescale.com/)
- [Keycloak Database Setup](https://www.keycloak.org/server/db)
