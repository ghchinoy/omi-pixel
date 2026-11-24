#!/usr/bin/env bash
set -euo pipefail

# omi-pixel Cloud Run deployment script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "${SCRIPT_DIR}/../service" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "Error: ${ENV_FILE} not found. Please create it from .env.template and run setup.sh first."
  exit 1
fi

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${SERVICE_NAME:-omi-pixel-service}"
DATABASE="${FIRESTORE_DATABASE:-omi-pixel}"
LOCATION="${GOOGLE_CLOUD_LOCATION:-global}"
if [[ -z "${GCS_BUCKET:-}" || "${GCS_BUCKET}" == *"your-gcp-project-id"* ]]; then
  BUCKET="${PROJECT_ID}-omi-pixel-audio"
else
  BUCKET="${GCS_BUCKET}"
fi
AUTH_DISABLED="${AUTH_DISABLED:-false}"
FIREBASE_API_KEY="${FIREBASE_API_KEY:-}"
FIREBASE_APP_ID="${FIREBASE_APP_ID:-}"
FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID:-}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.5-transcribe}"
GEMINI_LIVE_MODEL="${GEMINI_LIVE_MODEL:-gemini-3.5-transcribe-live}"
TITLE_MODEL="${TITLE_MODEL:-gemini-3.5-flash-lite}"
SUMMARY_MODEL="${SUMMARY_MODEL:-gemini-4-hydrogen}"
SA_NAME="${SERVICE_ACCOUNT_NAME:-sa-omi-pixel}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "your-gcp-project-id" ]]; then
  echo "Error: GOOGLE_CLOUD_PROJECT must be set in ${ENV_FILE}"
  exit 1
fi

echo "==> Deploying ${SERVICE} to Cloud Run in ${REGION} (Project: ${PROJECT_ID}, SA: ${SA_EMAIL}, GCS: gs://${BUCKET}, Vertex: ${LOCATION}, Summary: ${SUMMARY_MODEL})..."

gcloud run deploy "${SERVICE}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --service-account="${SA_EMAIL}" \
  --source="${SERVICE_DIR}" \
  --set-env-vars="GOOGLE_CLOUD_PROJECT=${PROJECT_ID},FIRESTORE_DATABASE=${DATABASE},GOOGLE_CLOUD_LOCATION=${LOCATION},GCS_BUCKET=${BUCKET},AUTH_DISABLED=${AUTH_DISABLED},FIREBASE_API_KEY=${FIREBASE_API_KEY},FIREBASE_APP_ID=${FIREBASE_APP_ID},FIREBASE_MESSAGING_SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID},GEMINI_MODEL=${GEMINI_MODEL},GEMINI_LIVE_MODEL=${GEMINI_LIVE_MODEL},TITLE_MODEL=${TITLE_MODEL},SUMMARY_MODEL=${SUMMARY_MODEL}" \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=5 \
  --memory=512Mi \
  --cpu=1 \
  --timeout=3600

SERVICE_URL=$(gcloud run services describe "${SERVICE}" --project="${PROJECT_ID}" --region="${REGION}" --format='value(status.url)')
SERVICE_HOST="${SERVICE_URL#https://}"
echo "==> Successfully deployed to Cloud Run!"
echo "==> Service URL: ${SERVICE_URL}"
echo "==> Web Review UI: ${SERVICE_URL}/"
echo "==> API Endpoint: ${SERVICE_URL}/api/sessions"
echo ""
echo "Reminder (first-time setup): ensure '${SERVICE_HOST}' is listed under Firebase Authorized Domains:"
echo "  https://console.firebase.google.com/project/${PROJECT_ID}/authentication/settings"
echo ""
echo "Next: run ./postflight.sh (or 'make postflight') to verify service health and Firestore connectivity."
