#!/bin/bash

# Validate the DISCORD_WEBHOOK environment variable
# Usage in another script:
#      if ${SCRIPTS_DIR}/validate-discord-webhook.sh; then
#          echo "Valid webhook"
#      else
#          echo "Invalid webhook"
#      fi

# Regex for basic URL validation
VALID_URL_REGEX="^https://discord\.com/api/webhooks/[0-9]+/[a-zA-Z0-9_.-]+$"

# Check if DISCORD_WEBHOOK is set and not empty
if [ -z "${DISCORD_WEBHOOK}" ]; then
  exit 1
fi

# Validate the URL format
if ! [[ "${DISCORD_WEBHOOK}" =~ ${VALID_URL_REGEX} ]]; then
  exit 1
fi

exit 0