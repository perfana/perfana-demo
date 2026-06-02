-- ================================================================================================
-- Create the Grafana database in the shared PostgreSQL instance
-- ================================================================================================
-- Grafana stores its own backend state here (see grafana/grafana.ini).
-- Runs only on first initialization of an empty postgres data volume.
-- ================================================================================================

-- Create grafana database
CREATE DATABASE grafana;

-- Grant privileges to perfana user
GRANT ALL PRIVILEGES ON DATABASE grafana TO perfana;

-- Connect to grafana database and grant schema privileges
\c grafana
GRANT ALL ON SCHEMA public TO perfana;

SELECT 'Grafana database created successfully' AS status;
