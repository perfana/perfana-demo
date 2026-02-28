-- ================================================================================================
-- PERFANA POSTGRES INITIALIZATION SCRIPT
-- ================================================================================================
-- This script creates the keycloak database in the shared postgres instance
-- ================================================================================================

-- Create keycloak database
CREATE DATABASE keycloak;

-- Grant privileges to perfana user
GRANT ALL PRIVILEGES ON DATABASE keycloak TO perfana;

-- Connect to keycloak database and set up schema
\c keycloak

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO perfana;

-- Log completion
SELECT 'Keycloak database created successfully' AS status;
