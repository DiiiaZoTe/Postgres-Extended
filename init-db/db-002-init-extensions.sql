-- ! Add this to the initial migration script
-- ! This requires a restart of the postgres container before execution
-- ! in order for the intial postgres.conf to be updated

----------------------------------------------------------------
-- Drop the postgres database (default empty database)
----------------------------------------------------------------
DROP DATABASE IF EXISTS postgres WITH (FORCE);

----------------------------------------------------------------
-- Add required extensions
----------------------------------------------------------------

-- TimescaleDB (must be first)
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Other extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS plsh;
CREATE EXTENSION IF NOT EXISTS pg_repack;

----------------------------------------------------------------
-- Verify the extensions
----------------------------------------------------------------
SELECT * FROM pg_available_extensions WHERE installed_version IS NOT NULL;

----------------------------------------------------------------
-- Schedule backup script to run every minute
----------------------------------------------------------------
CREATE OR REPLACE FUNCTION backup(backup_type text DEFAULT 'full') RETURNS void AS $$
#!/bin/sh
${SCRIPTS_DIR}/backup.sh $1
$$ LANGUAGE plsh;

CREATE OR REPLACE FUNCTION cron_backup(backup_type text DEFAULT 'full') RETURNS void AS $$
#!/bin/sh
if [ "${CRON_BACKUP_ENABLED}" = "true" ]; then
  ${SCRIPTS_DIR}/backup.sh $1 ;
fi
$$ LANGUAGE plsh;

-- Schedule full backup to run every Sunday at 00:00
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM cron.job WHERE schedule = '0 0 * * 0' AND jobname = 'full_backup'
    ) THEN PERFORM cron.schedule('full_backup', '0 0 * * 0', 'SELECT cron_backup(''full'')');
    END IF;
END $$;

-- Schedule incremental backup to run Monday through Saturday at 00:00
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM cron.job WHERE schedule = '0 0 * * 1-6' AND jobname = 'incremental_backup'
    ) THEN PERFORM cron.schedule('incremental_backup', '0 0 * * 1-6', 'SELECT cron_backup(''incremental'')');
    END IF;
END $$;

----------------------------------------------------------------
-- Verify the cron jobs
----------------------------------------------------------------
SELECT * FROM cron.job;