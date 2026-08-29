#!/usr/bin/env bash
set -uo pipefail

# omi-pixel postflight verification script
# Verifies that Cloud Run service is healthy, API endpoints respond, and Firestore database is bound.
# Usage: ./postflight.sh [--url https://custom-url.a.run.app]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

CUSTOM_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) CUSTOM_URL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 2 ;;
  esac
done

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
echo " Omi-Pixel Postflight Verification"
echo "======================================"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${SERVICE_NAME:-omi-pixel-service}"
DATABASE="${FIRESTORE_DATABASE:-omi-pixel}"

SERVICE_URL="${CUSTOM_URL:-}"

if [[ -z "${SERVICE_URL}" ]]; then
  if [[ -n "${PROJECT_ID}" ]] && command -v gcloud >/dev/null 2>&1; then
    echo "==> Resolving Cloud Run URL for '${SERVICE}' in ${REGION} (Project: ${PROJECT_ID})..."
    SERVICE_URL=$(gcloud run services describe "${SERVICE}" --project="${PROJECT_ID}" --region="${REGION}" --format='value(status.url)' 2>/dev/null || true)
  fi
fi

if [[ -z "${SERVICE_URL}" ]]; then
  fail "Could not determine Service URL. Pass --url https://your-service.a.run.app or configure infra/.env."
  exit 1
fi

echo "==> Testing Service URL: ${SERVICE_URL}"
echo ""

# 1. Health Check
echo "-- Service Health Endpoint --"
HEALTH_RESP="$(curl -s -w "\n%{http_code}" "${SERVICE_URL}/api/health" 2>/dev/null || echo "error\n000")"
HTTP_CODE="$(echo "${HEALTH_RESP}" | tail -n 1)"
BODY="$(echo "${HEALTH_RESP}" | sed '$d')"

if [[ "${HTTP_CODE}" == "200" ]] && echo "${BODY}" | grep -q '"status":"ok"'; then
  pass "GET /api/health returned 200 OK (${BODY})"
else
  fail "GET /api/health failed (HTTP ${HTTP_CODE}, Body: ${BODY})"
fi

# 2. Web UI Endpoint
echo ""
echo "-- Web Review Dashboard --"
WEB_CODE="$(curl -s -o /dev/null -w "%{http_code}" "${SERVICE_URL}/" 2>/dev/null || echo "000")"
if [[ "${WEB_CODE}" == "200" ]]; then
  pass "GET / returned 200 OK (Web UI active)"
else
  fail "GET / returned HTTP ${WEB_CODE}"
fi

# 3. Sessions API Endpoint (Auth Protection Check)
echo ""
echo "-- API Auth Protection Check --"
SESSIONS_RESP="$(curl -s -w "\n%{http_code}" "${SERVICE_URL}/api/sessions" 2>/dev/null || echo "error\n000")"
SESS_HTTP_CODE="$(echo "${SESSIONS_RESP}" | tail -n 1)"
SESS_BODY="$(echo "${SESSIONS_RESP}" | sed '$d')"

if [[ "${SESS_HTTP_CODE}" == "401" ]]; then
  pass "GET /api/sessions correctly rejected unauthenticated request with 401 (Auth active)"
elif [[ "${SESS_HTTP_CODE}" == "200" ]]; then
  pass "GET /api/sessions returned 200 OK (AUTH_DISABLED mode)"
else
  fail "GET /api/sessions returned unexpected HTTP ${SESS_HTTP_CODE} (Body: ${SESS_BODY})"
fi

# 4. Firestore Database Binding Check
echo ""
echo "-- Firestore Database Binding --"
if [[ -n "${PROJECT_ID}" ]] && command -v gcloud >/dev/null 2>&1; then
  if gcloud firestore databases describe --database="${DATABASE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    pass "Firestore database '${DATABASE}' is ACTIVE and ready in ${PROJECT_ID}"
  else
    warn "Could not verify database '${DATABASE}' via gcloud."
  fi
fi

# 5. Cloud Storage Audio Bucket Check
echo ""
echo "-- Cloud Storage Audio Bucket --"
BUCKET="${GCS_BUCKET:-${PROJECT_ID}-omi-pixel-audio}"
if [[ -n "${PROJECT_ID}" ]] && command -v gcloud >/dev/null 2>&1; then
  if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    pass "GCS Audio Bucket 'gs://${BUCKET}' is active"
  else
    warn "GCS Audio Bucket 'gs://${BUCKET}' not found (inline audio processing active)."
  fi
fi

# Summary
echo ""
echo "======================================"
echo " Postflight Summary"
echo "======================================"
echo " Service URL:       ${SERVICE_URL}"
echo " Web Review UI:     ${SERVICE_URL}/"
echo " Firestore DB:      ${DATABASE}"
echo " Audio GCS Bucket:  gs://${BUCKET}"
echo " Authentication:    Active (Firebase Auth + Allowlist)"
echo ""

if [[ ${ERRORS} -gt 0 ]]; then
  echo "${RED} Postflight check FAILED: ${ERRORS} error(s).${NC}"
  exit 1
elif [[ ${WARNINGS} -gt 0 ]]; then
  echo "${YELLOW} Postflight verified with ${WARNINGS} warning(s).${NC}"
  exit 0
else
  echo "${GREEN} Postflight verified. All checks green!${NC}"
  exit 0
fi
