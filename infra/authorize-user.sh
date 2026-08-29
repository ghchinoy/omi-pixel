#!/usr/bin/env bash
set -euo pipefail

# omi-pixel user authorization script
# Adds or removes an email address from the Firestore authorized_users collection.
# Usage: ./authorize-user.sh <email> [--admin] [--remove]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

PROJECT="${GOOGLE_CLOUD_PROJECT:-}"
DATABASE="${FIRESTORE_DATABASE:-omi-pixel}"

if [[ -z "${PROJECT}" || "${PROJECT}" == "your-gcp-project-id" ]]; then
  echo "Error: GOOGLE_CLOUD_PROJECT must be set in ${ENV_FILE} or environment."
  exit 1
fi

EMAIL=""
ROLE="member"
REMOVE=false

for arg in "$@"; do
  case "${arg}" in
    --admin)
      ROLE="admin"
      ;;
    --remove)
      REMOVE=true
      ;;
    -*)
      echo "Unknown option: ${arg}"
      echo "Usage: ./authorize-user.sh <email> [--admin] [--remove]"
      exit 1
      ;;
    *)
      if [[ -z "${EMAIL}" ]]; then
        EMAIL="${arg}"
      fi
      ;;
  esac
done

if [[ -z "${EMAIL}" ]]; then
  echo "Error: email is required."
  echo "Usage: ./authorize-user.sh <email> [--admin] [--remove]"
  exit 1
fi

EMAIL_LC="$(echo "${EMAIL}" | tr '[:upper:]' '[:lower:]' | xargs)"

echo "==> Fetching Google Cloud authentication token..."
TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
if [[ -z "${TOKEN}" ]]; then
  echo "Error: Failed to obtain gcloud access token. Run: gcloud auth login"
  exit 1
fi

DOC_URL="https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/${DATABASE}/documents/authorized_users/${EMAIL_LC}"

if [[ "${REMOVE}" == true ]]; then
  echo "==> Removing '${EMAIL_LC}' from authorized_users (Project: ${PROJECT}, Database: ${DATABASE})..."
  HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${DOC_URL}" \
    -H "Authorization: Bearer ${TOKEN}")"

  if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "204" ]]; then
    echo "✓ Successfully removed '${EMAIL_LC}' from authorized_users."
  elif [[ "${HTTP_CODE}" == "404" ]]; then
    echo "ℹ User '${EMAIL_LC}' was not found in authorized_users."
  else
    echo "Error: Failed to remove user (HTTP ${HTTP_CODE})."
    exit 1
  fi
else
  echo "==> Authorizing '${EMAIL_LC}' with role '${ROLE}' (Project: ${PROJECT}, Database: ${DATABASE})..."
  NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  PAYLOAD=$(cat <<EOF
{
  "fields": {
    "email": { "stringValue": "${EMAIL_LC}" },
    "role": { "stringValue": "${ROLE}" },
    "added_at": { "timestampValue": "${NOW}" }
  }
}
EOF
)

  HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "${DOC_URL}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}")"

  if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "201" ]]; then
    echo "✓ Successfully authorized '${EMAIL_LC}' (role: ${ROLE}) in database '${DATABASE}'."
    echo "  Note: Cloud Run service caches allowlist for 60s. Restart local server or wait ~60s for cache refresh."
  else
    echo "Error: Failed to authorize user (HTTP ${HTTP_CODE})."
    exit 1
  fi
fi
