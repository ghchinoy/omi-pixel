#!/usr/bin/env bash
set -euo pipefail

# omi-pixel infrastructure setup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "No .env found at ${ENV_FILE}. Copying from .env.template..."
  cp "${SCRIPT_DIR}/.env.template" "${ENV_FILE}"
  echo "Please edit ${ENV_FILE} with your GOOGLE_CLOUD_PROJECT and FIRESTORE_DATABASE, then re-run setup.sh."
  exit 1
fi

if [[ -z "${GOOGLE_CLOUD_PROJECT:-}" || "${GOOGLE_CLOUD_PROJECT}" == "your-gcp-project-id" ]]; then
  echo "Error: GOOGLE_CLOUD_PROJECT must be set in ${ENV_FILE}"
  exit 1
fi

REGION="${GCP_REGION:-us-central1}"
DATABASE="${FIRESTORE_DATABASE:-omi-pixel}"
BUCKET="${GCS_BUCKET:-${GOOGLE_CLOUD_PROJECT}-omi-pixel-audio}"

SA_NAME="${SERVICE_ACCOUNT_NAME:-sa-omi-pixel}"
SA_EMAIL="${SA_NAME}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"

echo "==> Configuring gcloud project: ${GOOGLE_CLOUD_PROJECT}"
gcloud config set project "${GOOGLE_CLOUD_PROJECT}"

echo "==> Enabling required GCP APIs..."
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  firestore.googleapis.com \
  storage.googleapis.com \
  identitytoolkit.googleapis.com \
  aiplatform.googleapis.com \
  cloudbuild.googleapis.com

echo "==> Checking Cloud Run Service Account '${SA_NAME}'..."
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GOOGLE_CLOUD_PROJECT}" >/dev/null 2>&1; then
  echo "==> Creating Service Account '${SA_NAME}'..."
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${GOOGLE_CLOUD_PROJECT}" \
    --display-name="Omi Pixel Cloud Run Service Account"
else
  echo "==> Service Account '${SA_NAME}' already exists."
fi

echo "==> Granting IAM roles to '${SA_EMAIL}'..."
ROLES=(
  roles/aiplatform.user
  roles/datastore.user
  roles/storage.objectAdmin
  roles/firebaseauth.viewer
)

for role in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${GOOGLE_CLOUD_PROJECT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None >/dev/null 2>&1 || true
done

echo "==> Checking Firestore Database '${DATABASE}' in Native mode..."
if ! gcloud firestore databases describe --database="${DATABASE}" --project="${GOOGLE_CLOUD_PROJECT}" >/dev/null 2>&1; then
  echo "==> Creating Firestore Database '${DATABASE}' in region ${REGION} (Native Mode)..."
  if [[ "${DATABASE}" == "(default)" ]]; then
    gcloud firestore databases create --location="${REGION}" --type=firestore-native --project="${GOOGLE_CLOUD_PROJECT}" || true
  else
    gcloud firestore databases create --database="${DATABASE}" --location="${REGION}" --type=firestore-native --project="${GOOGLE_CLOUD_PROJECT}" || true
  fi
else
  echo "==> Firestore database '${DATABASE}' already exists."
fi

echo "==> Checking Google Cloud Storage bucket '${BUCKET}'..."
if ! gcloud storage buckets describe "gs://${BUCKET}" --project="${GOOGLE_CLOUD_PROJECT}" >/dev/null 2>&1; then
  echo "==> Creating Cloud Storage Bucket 'gs://${BUCKET}' in ${REGION}..."
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${GOOGLE_CLOUD_PROJECT}" \
    --location="${REGION}" \
    --uniform-bucket-level-access || true
else
  echo "==> Cloud Storage bucket 'gs://${BUCKET}' already exists."
fi

echo "==> Setting up Artifact Registry repository 'omi-pixel' in ${REGION}..."
if ! gcloud artifacts repositories describe omi-pixel --location="${REGION}" --project="${GOOGLE_CLOUD_PROJECT}" >/dev/null 2>&1; then
  gcloud artifacts repositories create omi-pixel \
    --project="${GOOGLE_CLOUD_PROJECT}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Docker repository for omi-pixel Cloud Run service"
else
  echo "==> Artifact repository 'omi-pixel' already exists."
fi

# Seed current active gcloud user into authorized_users
ACTIVE_USER="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 || true)"
if [[ -n "${ACTIVE_USER}" ]]; then
  echo "==> Seeding authorized_users in Firestore database '${DATABASE}' for '${ACTIVE_USER}'..."
  "${SCRIPT_DIR}/authorize-user.sh" "${ACTIVE_USER}" --admin
fi

echo "==> Infrastructure setup complete for project ${GOOGLE_CLOUD_PROJECT} (Firestore DB: ${DATABASE}, Bucket: gs://${BUCKET})!"
echo "Next: run ./preflight.sh to verify, then ./deploy.sh to deploy to Cloud Run."
