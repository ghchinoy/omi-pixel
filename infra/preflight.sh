#!/usr/bin/env bash
set -uo pipefail

# omi-pixel preflight validation script
# Read-only checks that must pass before deploying to Cloud Run.
# Usage: ./preflight.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Color helpers
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m'

ERRORS=0
WARNINGS=0

pass() { echo "${GREEN}[PASS]${NC} $1"; }
warn() { echo "${YELLOW}[WARN]${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS + 1)); }

echo "======================================"
echo " Omi-Pixel Preflight Check"
echo "======================================"

# 1. Required CLI tools
echo ""
echo "-- Required tooling --"
if command -v gcloud >/dev/null 2>&1; then
  pass "gcloud CLI found"
else
  fail "gcloud CLI not found. Install the Google Cloud SDK."
fi

if command -v go >/dev/null 2>&1; then
  pass "go toolchain found ($(go version | awk '{print $3}'))"
else
  fail "go toolchain not found. Install Go 1.23+."
fi

# Optional tools (warn only)
command -v flutter >/dev/null 2>&1 && pass "flutter found (optional)" || warn "flutter not found (needed only for the mobile app)"
command -v adb >/dev/null 2>&1 && pass "adb found (optional)" || warn "adb not found (needed only for sideloading to Pixel)"

# 2. Environment file and variables
echo ""
echo "-- Configuration (.env) --"
if [[ ! -f "${ENV_FILE}" ]]; then
  fail ".env not found at ${ENV_FILE}. Run: cp .env.template .env  (then edit)"
  echo ""
  echo "${RED}Preflight aborted: no .env file.${NC}"
  exit 1
fi
pass ".env file present"

# shellcheck disable=SC1090
source "${ENV_FILE}"

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
REGION="${GCP_REGION:-us-central1}"
DATABASE="${FIRESTORE_DATABASE:-}"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "your-gcp-project-id" ]]; then
  fail "GOOGLE_CLOUD_PROJECT is unset or still the placeholder in .env"
else
  pass "GOOGLE_CLOUD_PROJECT = ${PROJECT_ID}"
fi

if [[ -z "${DATABASE}" ]]; then
  fail "FIRESTORE_DATABASE is unset in .env (recommended: omi-pixel)"
elif [[ "${DATABASE}" == "(default)" ]]; then
  warn "FIRESTORE_DATABASE is '(default)'. A dedicated named database (e.g. omi-pixel) is best practice."
else
  pass "FIRESTORE_DATABASE = ${DATABASE}"
fi

# Stop here if fundamentals already broken (avoid noisy gcloud errors)
if [[ ${ERRORS} -gt 0 ]]; then
  echo ""
  echo "${RED}Preflight found ${ERRORS} error(s). Fix the above before continuing.${NC}"
  exit 1
fi

# 3. gcloud auth and active project
echo ""
echo "-- gcloud account & project --"
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  fail "No active gcloud account. Run: gcloud auth login"
else
  pass "Active account: ${ACTIVE_ACCOUNT}"
fi

ACTIVE_PROJECT="$(gcloud config get-value project 2>/dev/null)"
if [[ "${ACTIVE_PROJECT}" != "${PROJECT_ID}" ]]; then
  fail "Active gcloud project '${ACTIVE_PROJECT}' does not match GOOGLE_CLOUD_PROJECT '${PROJECT_ID}'."
  echo "       Fix: gcloud config set project ${PROJECT_ID}"
else
  pass "Active gcloud project matches (${ACTIVE_PROJECT})"
fi

# 4. Required APIs enabled
echo ""
echo "-- Enabled GCP APIs --"
REQUIRED_APIS=(run.googleapis.com firestore.googleapis.com storage.googleapis.com identitytoolkit.googleapis.com artifactregistry.googleapis.com aiplatform.googleapis.com)
ENABLED_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format='value(config.name)' 2>/dev/null || true)"
if [[ -z "${ENABLED_APIS}" ]]; then
  warn "Could not list enabled APIs (permission or auth issue). Skipping API checks."
else
  for api in "${REQUIRED_APIS[@]}"; do
    if echo "${ENABLED_APIS}" | grep -q "^${api}$"; then
      pass "API enabled: ${api}"
    else
      fail "API not enabled: ${api}  (run ./setup.sh)"
    fi
  done
fi

# 5. Firestore named database exists
echo ""
echo "-- Firestore database --"
if [[ -n "${DATABASE}" ]]; then
  DB_INFO="$(gcloud firestore databases describe --database="${DATABASE}" --project="${PROJECT_ID}" --format='value(type,locationId)' 2>/dev/null || true)"
  if [[ -n "${DB_INFO}" ]]; then
    pass "Firestore database '${DATABASE}' exists (${DB_INFO})"
  else
    fail "Firestore database '${DATABASE}' not found in project ${PROJECT_ID}. Run ./setup.sh to create it."
  fi
fi

# 6. Cloud Storage bucket exists
echo ""
echo "-- Cloud Storage Audio Bucket --"
BUCKET="${GCS_BUCKET:-${PROJECT_ID}-omi-pixel-audio}"
if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  pass "GCS Bucket 'gs://${BUCKET}' exists"
else
  warn "GCS Bucket 'gs://${BUCKET}' not found. Run ./setup.sh to create it (audio will fall back to inline processing)."
fi

# 7. Authorized Users allowlist check
echo ""
echo "-- Authorized Users Allowlist --"
if [[ -n "${ACTIVE_ACCOUNT}" && -n "${PROJECT_ID}" && -n "${DATABASE}" ]]; then
  TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
  EMAIL_LC="$(echo "${ACTIVE_ACCOUNT}" | tr '[:upper:]' '[:lower:]' | xargs)"
  CHECK_URL="https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/${DATABASE}/documents/authorized_users/${EMAIL_LC}"
  AUTHZ_CODE="$(curl -s -o /dev/null -w "%{http_code}" "${CHECK_URL}" -H "Authorization: Bearer ${TOKEN}" 2>/dev/null || echo "000")"
  if [[ "${AUTHZ_CODE}" == "200" ]]; then
    pass "Active user '${ACTIVE_ACCOUNT}' is AUTHORIZED in Firestore '${DATABASE}'"
  elif [[ "${AUTHZ_CODE}" == "404" ]]; then
    warn "Active user '${ACTIVE_ACCOUNT}' is NOT in authorized_users. Run: ./authorize-user.sh ${ACTIVE_ACCOUNT} --admin"
  else
    warn "Could not verify authorized_users status (HTTP ${AUTHZ_CODE})"
  fi
fi

# 8. Cloud Run Service Account check
echo ""
echo "-- Cloud Run Dedicated Service Account --"
SA_NAME="${SERVICE_ACCOUNT_NAME:-sa-omi-pixel}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  pass "Service Account '${SA_EMAIL}' exists"
else
  warn "Service Account '${SA_EMAIL}' not found. Run ./setup.sh to provision it."
fi

# Summary
echo ""
echo "======================================"
if [[ ${ERRORS} -gt 0 ]]; then
  echo "${RED} Preflight FAILED: ${ERRORS} error(s), ${WARNINGS} warning(s).${NC}"
  exit 1
elif [[ ${WARNINGS} -gt 0 ]]; then
  echo "${YELLOW} Preflight passed with ${WARNINGS} warning(s).${NC}"
  echo " Ready to deploy: ./deploy.sh"
  exit 0
else
  echo "${GREEN} Preflight passed. All checks green.${NC}"
  echo " Ready to deploy: ./deploy.sh"
  exit 0
fi
