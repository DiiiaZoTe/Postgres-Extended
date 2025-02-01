#!/bin/bash

# conf-change-env.sh
# This script is used to change the environment variables in the .conf files.
# This is needed to change some of the template variables.

# Logging function
log() {
  echo "[CONF-CHANGE-ENV] $*"
}

# Escape sed for special characters
escape_sed() {
  echo "$1" | sed -e 's/[\/&]/\\&/g'
}

# Replace template variables in a file
replace_template_variables() {
  local search="$1"
  local replace=$(escape_sed "$2")
  local file="$3"
  log "--> Replacing ${search} with ${replace} in ${file}"
  sed -i "s/${search}/${replace}/g" "$file"
}

log "environment variables: ${POSTGRES_DB} ${POSTGRES_USER} ${PGDATA}"

if [ -z "${POSTGRES_DB}" ] || [ -z "${POSTGRES_USER}" ] || [ -z "${PGDATA}" ]; then
  log "Error: Required environment variables are not set."
  exit 1
fi

###################################################################
# Replace template variables in custom.conf
###################################################################
log "Replacing template variables in ${POSTGRES_CUSTOM_CONF}..."

if [ ! -f "${POSTGRES_CUSTOM_CONF}" ]; then
  log "Error: ${POSTGRES_CUSTOM_CONF} not found."
  exit 1
fi

replace_template_variables "__DB_NAME__" "${POSTGRES_DB}" "${POSTGRES_CUSTOM_CONF}"
replace_template_variables "__BACKUP_STANZA__" "${PGBACKREST_STANZA}" "${POSTGRES_CUSTOM_CONF}"
replace_template_variables "__PG_DATA__" "${PGDATA}" "${POSTGRES_CUSTOM_CONF}"

log "Template variables replaced in ${POSTGRES_CUSTOM_CONF}."
