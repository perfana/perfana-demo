-- ================================================================================================
-- PRE-SEED MIGRATION RECORDS
-- ================================================================================================
-- The perfana-migration image runs all pending migrations in a single transaction.
-- ConsolidatedSchema creates the full schema (including all indexes), but
-- AddTagsHashUniqueIndex then tries to create an index that already exists,
-- causing the entire transaction to roll back.
--
-- This script pre-creates the typeorm_migrations table and inserts the
-- problematic migration record so it gets skipped during migration.
-- ================================================================================================

\c perfana

CREATE TABLE IF NOT EXISTS typeorm_migrations (
    id SERIAL PRIMARY KEY,
    "timestamp" BIGINT NOT NULL,
    name VARCHAR NOT NULL
);

INSERT INTO typeorm_migrations ("timestamp", name)
VALUES (1700000000003, 'AddTagsHashUniqueIndex1700000000003');

SELECT 'Migration records pre-seeded successfully' AS status;
