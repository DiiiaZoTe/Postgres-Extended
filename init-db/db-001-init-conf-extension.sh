#!/bin/bash
set -e

#******************************************************
#* init-conf-extension.sh
#* 1. Appends custom configuration to postgresql.conf
#* 2. Creates the stanza (pgbackrest)
#*     2.1 (before 1.) Disable archive_command in custom.conf first
#*     2.2 Restart postgres
#*     2.3 Create the stanza
#*     2.4 Re-enable archive_command in custom.conf
#*     2.5 Reload postgres
#*     2.6 Check if the stanza is created
#*     2.7 Run full backup for testing
#******************************************************

# Logging function
log() {
  echo "[INIT-CONF-EXTENSION] $*"
}

# Restart postgres function
restart_postgres() {
  pg_ctl -D "$PGDATA" -m fast stop
  sleep 3  # Give it time to stop properly
  pg_ctl -D "$PGDATA" -o "-c listen_addresses='localhost'" -w start
}

# Include custom config function (pass the custom config file as an argument)
include_custom_config() {
  local custom_conf=$1
  # Append custom configuration to postgresql.conf if not already included
  if ! grep -Fxq "include '${custom_conf}'" "${POSTGRES_CONF}"; then
      echo "include '${custom_conf}'" >> "${POSTGRES_CONF}"
      log "Custom configuration ${custom_conf} appended to ${POSTGRES_CONF}."
  else
      log "Custom configuration ${custom_conf} already included in ${POSTGRES_CONF}."
  fi
}

####################################################
# 1. Add custom.conf to postgresql.conf
####################################################

# Include custom config function (pass the custom config file as an argument)
include_custom_config "${TIMESCALE_CUSTOM_CONF}"
include_custom_config "${POSTGRES_CUSTOM_CONF}"

####################################################
# 2. Configure pgbackrest
####################################################

create_pgbackrest_stanza() {
  ####################################################
  # 2.1 Comment out the line for the archive_command in custom.conf (pgbackrest),
  ####################################################

  # because we need to create the stanza first before we can use it.
  log "Commenting out archive_command in ${POSTGRES_CUSTOM_CONF}..."
  sed -i "s/^archive_command/# archive_command/g" "${POSTGRES_CUSTOM_CONF}"
  log "Commented out archive_command in ${POSTGRES_CUSTOM_CONF}."

  ####################################################
  # 2.2 Restart postgres to apply the changes
  ####################################################

  log "Restarting postgres to apply the changes..."
  restart_postgres
  log "Restarted postgres."

  ####################################################
  # 2.3 Create the stanza
  ####################################################

  log "Creating the stanza..."
  pgbackrest --stanza=${PGBACKREST_STANZA} --pg1-path=${PGBACKREST_PG1_PATH} stanza-create
  log "Created the stanza."

  ####################################################
  # 2.4 Re-enable the archive in postgresql custom.conf
  ####################################################

  log "Re-enabling archive_command in ${POSTGRES_CUSTOM_CONF}..."
  sed -i "s/# archive_command/archive_command/g" "${POSTGRES_CUSTOM_CONF}"
  log "Re-enabled archive_command in ${POSTGRES_CUSTOM_CONF}."

  ####################################################
  # 2.5 Restart postgres to apply the changes
  ####################################################

  log "Restarting postgres to apply the changes..."
  restart_postgres
  log "Restarted postgres."

  ####################################################
  # 2.6 Check if the stanza is created
  ####################################################

  log "Checking if the stanza is created..."
  pgbackrest --stanza=${PGBACKREST_STANZA} --pg1-path=${PGBACKREST_PG1_PATH} check
  log "Checked if the stanza is created."

  ####################################################
  # 2.7 Run full backup for testing
  ####################################################
  log "Running full backup for testing..."
  ${SCRIPTS_DIR}/backup.sh full
  log "Full backup for testing completed."
}

if [ "${ENABLE_BACKUP}" = "off" ]; then
  log "Backup is disabled. Skipping pgbackrest configuration."
else
  create_pgbackrest_stanza
fi

####################################################
# FINAL. Restart postgres and continue with the next script
####################################################

log "Restarting postgres and continuing with the next script..."
restart_postgres
log "Restarted postgres and continued with the next script."

log "init-conf-extension.sh complete."