#!/bin/bash
set -e

####################################################
# Custom entrypoint script
# Is executed when the container is started
####################################################

# Logging function
log() {
  echo "[ENTRYPOINT] $*"
}

log "Starting entrypoint script..."

# ! DO SOMETHING HERE IF NEEDED

# Pass control back to the default PostgreSQL entrypoint
log "Custom setup complete. Passing control to PostgreSQL's default entrypoint..."
exec docker-entrypoint.sh "$@"