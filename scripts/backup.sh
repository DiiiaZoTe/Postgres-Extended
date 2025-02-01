#!/usr/bin/env bash
set -e

#****************************************************************************
#* Backup script for pgBackRest
#* Allows for incremental and full backups
#* Usage: ./backup.sh [incremental|full]
#****************************************************************************

#############################################################################
# To run a recovery to previous backup:
# 1. Stop the postgres service
#    supervisorctl stop postgres; supervisorctl update;
# 2. Copy the current data directory to a backup directory
#    cp -r ${PGDATA} ${PGVOLUME}/(project-name)-pgdata-safety
# 3. Switch to postgres user
#    su postgres
# 4. You may need to remove postmaster.pid (but make sure postgres is not running)
#    rm -f ${PGDATA}/postmaster.pid
# 5. Start pgbackrest restore (or look into point-in-time recovery in manual)
#    pgbackrest restore --stanza=${PGBACKREST_STANZA} --delta
# 6. Exit postgres user cntl+D, then start the postgres service
#    supervisorctl start postgres; supervisorctl update;
#############################################################################


#############################################################################
# Create functions
#############################################################################

# Set Variables
LOG_FILE=${PGVOLUME}/postgres-backup.log

# Function for general logging
function log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local log_message="[${timestamp}] [${level}] ${message}"
  printf "${log_message}\n\n" | tee -a "$LOG_FILE"

  # Send to Discord
  if ${SCRIPTS_DIR}/validate-discord-webhook.sh; then
    # escape \n and \r
    log_message=$(echo "${log_message}" | sed ':a;N;$!ba;s/\"/\\"/g;s/\n/\\n/g;s/\r/\\r/g')
    curl -s -H "Content-Type: application/json" -X POST -d "{\"content\": \"${log_message}\"}" "${DISCORD_WEBHOOK}" \
      >/dev/null 2>&1 || echo "Failed to send log to Discord." >> "$LOG_FILE"
  fi
}

# Trap errors for centralized error handling
function error_handler() {
  local exit_code=$?
  local last_command=${BASH_COMMAND}
  log "ERROR" "Command '${last_command}' failed with exit code ${exit_code}."
  exit $exit_code
}
# Set trap for any error
trap 'error_handler' ERR

# Validate required environment variables
function validate_env_vars() {
  local required_vars=("PGBACKREST_STANZA" "PGDATA" "SCRIPTS_DIR")
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
      log "ERROR" "Required environment variable '${var}' is not set.";
      exit 1;
    fi
  done
}

# Function to get the last backup info
function get_last_backup() {
  pgbackrest info --output=json | jq -r '
    def humanize(bytes):
      def round_to_two_decimals(value):
        (value * 100 | round) / 100;
      def unit_suffixes: ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
      def calculate(value; units):
        if (value < 1024.0 or (units | length) == 1) then
          "\(round_to_two_decimals(value)) \(units[0])"
        else
          calculate((value / 1024.0); (units[1:]))
        end;
      calculate(bytes; unit_suffixes);

    def format_backup_type(type):
      if type == "full" then
        "Full"
      elif type == "incr" then
        "Incremental"
      elif type == "diff" then
        "Differential"
      else
        type
      end;

    .[] |
    "Repository: " + .name,
    "Status: " + .status.message,
    (
      .backup | sort_by(.timestamp.stop) | last |
      "Backup Type: " + format_backup_type(.type) + "\n" +
      "Backup Name: " + .label + "\n" +
      "Start Time: " + (.timestamp.start | strftime("%Y-%m-%d %H:%M:%S")) + "\n" +
      "Stop Time: " + (.timestamp.stop | strftime("%Y-%m-%d %H:%M:%S")) + "\n" +
      "Database Size: " + (humanize(.info.size)) + "\n" +
      "Backup Size: " + (humanize(.info.repository.size))
    )
  '
}

# Main script logic
function run_backup() {
  case "$1" in
    incremental)
      log "INFO" "⏳ Running incremental backup for ${PGBACKREST_STANZA}"
      pgbackrest --stanza="${PGBACKREST_STANZA}" --pg1-path="${PGBACKREST_PG1_PATH}" --type=incr backup
      local last_backup_info=$(get_last_backup)
      log "INFO" "✅ Incremental backup for ${PGBACKREST_STANZA} completed:\n${last_backup_info}"
      ;;

    full)
      log "INFO" "⏳ Running full backup for ${PGBACKREST_STANZA}"
      pgbackrest --stanza="${PGBACKREST_STANZA}" --pg1-path="${PGBACKREST_PG1_PATH}" --type=full backup
      local last_backup_info=$(get_last_backup)
      log "INFO" "✅ Full backup for ${PGBACKREST_STANZA} completed:\n${last_backup_info}"
      ;;
    *)
      log "ERROR" "Invalid backup type: $1. Usage: $0 [incremental|full]"
      exit 1
      ;;
  esac
}

#############################################################################
# Execution
#############################################################################

# Validate environment variables
validate_env_vars

# Run the backup
if [[ $# -eq 0 ]]; then
  log "ERROR" "No backup type provided. Usage: $0 [incremental|full]"
  exit 1
else
  run_backup "$1"
fi