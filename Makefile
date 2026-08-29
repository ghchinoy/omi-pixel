# Omi-Pixel Makefile
# Convenient workflows for development, testing, authorization, and Cloud Run deployment.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Load environment configuration if present
-include infra/.env
export

GOOGLE_CLOUD_PROJECT ?= your-gcp-project-id
GOOGLE_CLOUD_LOCATION ?= global
FIRESTORE_DATABASE ?= omi-pixel
GCS_BUCKET ?= $(GOOGLE_CLOUD_PROJECT)-omi-pixel-audio
FIREBASE_API_KEY ?=
FIREBASE_APP_ID ?=
FIREBASE_MESSAGING_SENDER_ID ?=
PORT ?= 8080

.PHONY: help run-local run-local-noauth run-app adb-reverse configure-firebase authorize deauthorize setup preflight deploy postflight release test analyze build-apk icons clean

## help: Display this help message
help:
	@echo "======================================================================="
	@echo "                      OMI-PIXEL DEVELOPMENT WORKFLOW                  "
	@echo "======================================================================="
	@echo ""
	@echo "Local Development:"
	@echo "  make run-local           Run Go backend locally (Firebase Auth active)"
	@echo "  make run-local-noauth    Run Go backend locally with AUTH_DISABLED=true"
	@echo "  make run-app             Run Flutter app on connected Android Pixel device"
	@echo "  make adb-reverse         Reverse proxy port $(PORT) from Pixel to local Mac"
	@echo "  make configure-firebase  Generate Firebase app configs via flutterfire CLI"
	@echo ""
	@echo "User Authorization:"
	@echo "  make authorize EMAIL=user@domain.com [ADMIN=true]  Authorize user in Firestore"
	@echo "  make deauthorize EMAIL=user@domain.com            Remove user from Firestore"
	@echo ""
	@echo "Cloud Infrastructure & Deployment:"
	@echo "  make setup             Provision APIs, Firestore DB, and GCS bucket"
	@echo "  make preflight         Run pre-deployment validation checks"
	@echo "  make deploy            Build and deploy Go service to Google Cloud Run"
	@echo "  make postflight        Verify Cloud Run health, Firestore, and GCS"
	@echo "  make release           Execute preflight -> deploy -> postflight pipeline"
	@echo ""
	@echo "Quality & Testing:"
	@echo "  make test              Run unit tests for Go backend and Flutter app"
	@echo "  make analyze           Run linter and static analysis on Go and Flutter"
	@echo "  make build-apk         Build release Android APK (app-release.apk)"
	@echo "  make icons             Regenerate all Android/iOS app launcher icons"
	@echo ""

## run-local: Run Go backend locally with Firebase Auth and ADC Vertex AI
run-local:
	@echo "==> Starting Omi-Pixel service on port $(PORT) (Project: $(GOOGLE_CLOUD_PROJECT), Auth: Enabled)..."
	cd service && \
	GOOGLE_CLOUD_PROJECT=$(GOOGLE_CLOUD_PROJECT) \
	GOOGLE_CLOUD_LOCATION=$(GOOGLE_CLOUD_LOCATION) \
	FIRESTORE_DATABASE=$(FIRESTORE_DATABASE) \
	GCS_BUCKET=$(GCS_BUCKET) \
	FIREBASE_API_KEY=$(FIREBASE_API_KEY) \
	FIREBASE_APP_ID=$(FIREBASE_APP_ID) \
	FIREBASE_MESSAGING_SENDER_ID=$(FIREBASE_MESSAGING_SENDER_ID) \
	AUTH_DISABLED=false \
	PORT=$(PORT) \
	go run .

## run-local-noauth: Run Go backend locally in offline bypass mode (AUTH_DISABLED=true)
run-local-noauth:
	@echo "==> Starting Omi-Pixel service on port $(PORT) (AUTH_DISABLED=true)..."
	cd service && \
	GOOGLE_CLOUD_PROJECT=$(GOOGLE_CLOUD_PROJECT) \
	GOOGLE_CLOUD_LOCATION=$(GOOGLE_CLOUD_LOCATION) \
	FIRESTORE_DATABASE=$(FIRESTORE_DATABASE) \
	GCS_BUCKET=$(GCS_BUCKET) \
	AUTH_DISABLED=true \
	PORT=$(PORT) \
	go run .

## run-app: Run Flutter companion app on connected device/emulator
run-app:
	@echo "==> Running Flutter companion app on connected device..."
	cd app && flutter run

## configure-firebase: Run flutterfire configure for GOOGLE_CLOUD_PROJECT
configure-firebase:
	@if [ -z "$(GOOGLE_CLOUD_PROJECT)" ] || [ "$(GOOGLE_CLOUD_PROJECT)" = "your-gcp-project-id" ]; then \
		echo "Error: Set GOOGLE_CLOUD_PROJECT in infra/.env or pass GOOGLE_CLOUD_PROJECT=your-project-id"; \
		exit 1; \
	fi
	@echo "==> Configuring Firebase for project $(GOOGLE_CLOUD_PROJECT)..."
	cd app && flutterfire configure --project=$(GOOGLE_CLOUD_PROJECT)

## adb-reverse: Set up ADB reverse port forwarding for local testing over USB
adb-reverse:
	@echo "==> Setting up ADB reverse tcp:$(PORT) -> tcp:$(PORT)..."
	adb reverse tcp:$(PORT) tcp:$(PORT)
	@echo "✓ Pixel can now connect to Cloud Run service at http://localhost:$(PORT)"

## authorize: Authorize an email address in the Firestore allowlist (e.g. make authorize EMAIL=you@gmail.com ADMIN=true)
authorize:
	@if [ -z "$(EMAIL)" ]; then \
		echo "Error: EMAIL is required. Example: make authorize EMAIL=user@domain.com [ADMIN=true]"; \
		exit 1; \
	fi
	@./infra/authorize-user.sh $(EMAIL) $(if $(filter true,$(ADMIN)),--admin,)

## deauthorize: Remove an email address from the Firestore allowlist
deauthorize:
	@if [ -z "$(EMAIL)" ]; then \
		echo "Error: EMAIL is required. Example: make deauthorize EMAIL=user@domain.com"; \
		exit 1; \
	fi
	@./infra/authorize-user.sh $(EMAIL) --remove

## setup: Provision Google Cloud project resources (Firestore, Storage, APIs)
setup:
	@./infra/setup.sh

## preflight: Validate GCP project, APIs, databases, and authorization
preflight:
	@./infra/preflight.sh

## deploy: Deploy the Go backend service to Google Cloud Run
deploy:
	@./infra/deploy.sh

## postflight: Verify deployed Cloud Run service health and bindings
postflight:
	@./infra/postflight.sh

## release: Full deployment pipeline (preflight -> deploy -> postflight)
release: preflight deploy postflight

## test: Run unit tests across Go backend and Flutter mobile companion
test:
	@echo "==> Running Go backend unit tests..."
	cd service && go test -v ./...
	@echo ""
	@echo "==> Running Flutter app unit tests..."
	cd app && flutter test

## analyze: Run static analysis and linting checks
analyze:
	@echo "==> Running Go vet..."
	cd service && go vet ./...
	@echo ""
	@echo "==> Running Flutter analyze..."
	cd app && flutter analyze

## build-apk: Build standalone release APK for Google Pixel sideloading
build-apk:
	@echo "==> Building Flutter release APK..."
	cd app && flutter build apk --release
	@echo "✓ Release APK: app/build/app/outputs/flutter-apk/app-release.apk"

## icons: Regenerate app launcher icons from master asset
icons:
	@echo "==> Regenerating launcher icons..."
	cd app && dart run flutter_launcher_icons

## clean: Clean build artifacts
clean:
	@echo "==> Cleaning build artifacts..."
	cd app && flutter clean
	rm -f service/service
