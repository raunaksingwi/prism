#!/bin/bash

###############################################################################
# Firebase Test Lab Multilingual Runner
#
# This script runs Firebase Test Lab robo tests across multiple locales
# and organizes screenshots by language.
#
# Usage:
#   ./run-ftl-multilang.sh [options]
#
# Options:
#   --service-account-key <path>  Path to GCP service account JSON key (required)
#   --phone <number>              Test phone number (required)
#   --otp <code>                  Test OTP code (required)
#   --project-id <id>             GCP project ID (optional)
#   --bucket <name>               GCS bucket name (optional)
#   --locales <list>              Comma-separated locales (default: en,hi)
#   --devices <list>              Comma-separated devices (optional)
#   --apk-path <path>             Path to APK (default: auto-detect)
#   --skip-build                  Skip APK build
#   --analyze                     Run Claude analysis
#   --help                        Show help
#
# Example:
#   ./run-ftl-multilang.sh \
#     --service-account-key ~/gcp-key.json \
#     --phone 9876543210 \
#     --otp 123456 \
#     --locales en,hi,es
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
SKIP_BUILD=false
RUN_ANALYSIS=false
SERVICE_ACCOUNT_KEY=""
TEST_PHONE=""
TEST_OTP=""
PROJECT_ID=""
BUCKET_NAME=""
LOCALES="en,hi"
DEVICES=""
APK_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --service-account-key) SERVICE_ACCOUNT_KEY="$2"; shift 2 ;;
    --phone) TEST_PHONE="$2"; shift 2 ;;
    --otp) TEST_OTP="$2"; shift 2 ;;
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --bucket) BUCKET_NAME="$2"; shift 2 ;;
    --locales) LOCALES="$2"; shift 2 ;;
    --devices) DEVICES="$2"; shift 2 ;;
    --apk-path) APK_PATH="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --analyze) RUN_ANALYSIS=true; shift ;;
    --help) head -n 30 "$0" | tail -n +3; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

# Validate
if [ -z "$SERVICE_ACCOUNT_KEY" ] || [ ! -f "$SERVICE_ACCOUNT_KEY" ]; then
  echo -e "${RED}Error: Valid --service-account-key required${NC}"
  exit 1
fi

if [ -z "$TEST_PHONE" ] || [ -z "$TEST_OTP" ]; then
  echo -e "${RED}Error: --phone and --otp required${NC}"
  exit 1
fi

# Get project ID
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(grep -o '"project_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$SERVICE_ACCOUNT_KEY" | sed 's/"project_id"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
  if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: Could not extract project_id${NC}"
    exit 1
  fi
  echo -e "${GREEN}Found project ID: $PROJECT_ID${NC}"
fi

# Generate bucket name
if [ -z "$BUCKET_NAME" ]; then
  BUCKET_NAME="bhume-ftl-multilang-$(date +%s)"
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Firebase Test Lab Multilingual Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Project Root: $PROJECT_ROOT"
echo -e "GCP Project: $PROJECT_ID"
echo -e "GCS Bucket: $BUCKET_NAME"
echo -e "Locales: $LOCALES"
echo -e "${BLUE}========================================${NC}\n"

# Check dependencies
echo -e "${BLUE}Checking dependencies...${NC}"
if ! command -v gcloud &> /dev/null; then
  echo -e "${RED}Error: gcloud CLI not found${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Dependencies OK${NC}\n"

# Authenticate
echo -e "${BLUE}Authenticating with Google Cloud...${NC}"
gcloud auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY"
gcloud config set project "$PROJECT_ID"
echo -e "${GREEN}✓ Authenticated${NC}\n"

# Check/create bucket
echo -e "${BLUE}Checking GCS bucket...${NC}"
if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
  echo -e "${GREEN}✓ Bucket exists${NC}\n"
else
  echo -e "${YELLOW}Creating bucket...${NC}"
  gsutil mb -p "$PROJECT_ID" "gs://$BUCKET_NAME"
  echo -e "${GREEN}✓ Bucket created${NC}\n"
fi

# Detect or build APK
if [ -z "$APK_PATH" ]; then
  # Try to find APK in sample-app
  APK_PATH="$PROJECT_ROOT/sample-app/app/build/outputs/apk/debug/app-debug.apk"

  if [ "$SKIP_BUILD" = false ] || [ ! -f "$APK_PATH" ]; then
    echo -e "${BLUE}Building APK...${NC}"
    cd "$PROJECT_ROOT/sample-app"
    ./gradlew clean assembleDebug --no-daemon
    echo -e "${GREEN}✓ APK built${NC}\n"
  else
    echo -e "${YELLOW}Using existing APK${NC}\n"
  fi
fi

if [ ! -f "$APK_PATH" ]; then
  echo -e "${RED}Error: APK not found at $APK_PATH${NC}"
  exit 1
fi

echo -e "${GREEN}✓ APK found: $APK_PATH${NC}\n"

# Default devices if not specified
if [ -z "$DEVICES" ]; then
  DEVICES="starlte,version=29;redfin,version=30;husky,version=34"
fi

# Convert comma-separated locales to array
IFS=',' read -ra LOCALE_ARRAY <<< "$LOCALES"

# Run tests for each locale
SCREENSHOTS_BASE="$PROJECT_ROOT/ftl-scripts/screenshots/$TIMESTAMP"
mkdir -p "$SCREENSHOTS_BASE"

for locale in "${LOCALE_ARRAY[@]}"; do
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}Testing Locale: $locale${NC}"
  echo -e "${BLUE}========================================${NC}\n"

  RESULTS_DIR="ftl-results-$TIMESTAMP-$locale"
  LOCALE_SCREENSHOTS="$SCREENSHOTS_BASE/$locale"
  mkdir -p "$LOCALE_SCREENSHOTS"

  # Build device list with locale
  DEVICE_LIST=""
  IFS=';' read -ra DEVICE_SPECS <<< "$DEVICES"
  for device_spec in "${DEVICE_SPECS[@]}"; do
    if [ -n "$DEVICE_LIST" ]; then
      DEVICE_LIST="$DEVICE_LIST --device"
    fi
    DEVICE_LIST="$DEVICE_LIST model=${device_spec},locale=${locale},orientation=portrait"
  done

  # Run FTL
  echo -e "${BLUE}Running tests for locale: $locale${NC}"
  gcloud firebase test android run \
    --type robo \
    --app "$APK_PATH" \
    --device $DEVICE_LIST \
    --timeout 10m \
    --results-bucket "$BUCKET_NAME" \
    --results-dir "$RESULTS_DIR" \
    --format="json" > "$SCRIPT_DIR/ftl-results-$locale.json" 2>&1 || true

  echo -e "${GREEN}✓ Tests completed for $locale${NC}\n"

  # Download screenshots
  echo -e "${BLUE}Downloading screenshots for $locale...${NC}"
  gsutil -m cp -r "gs://$BUCKET_NAME/$RESULTS_DIR/" "$LOCALE_SCREENSHOTS/" 2>/dev/null || {
    echo -e "${YELLOW}Warning: Could not download some results${NC}"
  }

  # Count screenshots
  count=$(find "$LOCALE_SCREENSHOTS" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
  echo -e "${GREEN}✓ Downloaded $count screenshots for $locale${NC}\n"
done

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}All Tests Complete!${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "${BLUE}=== Screenshots Summary ===${NC}"
total_screenshots=0
for locale in "${LOCALE_ARRAY[@]}"; do
  locale_dir="$SCREENSHOTS_BASE/$locale"
  if [ -d "$locale_dir" ]; then
    count=$(find "$locale_dir" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    total_screenshots=$((total_screenshots + count))
    echo -e "${GREEN}$locale: $count screenshots${NC}"
  fi
done
echo -e "${GREEN}Total: $total_screenshots screenshots${NC}\n"

echo -e "Results saved to: $SCREENSHOTS_BASE"
echo -e "GCS Bucket: gs://$BUCKET_NAME"
echo -e "${BLUE}========================================${NC}\n"

# Open screenshots folder (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo -e "${BLUE}Opening screenshots folder...${NC}"
  open "$SCREENSHOTS_BASE"
fi

echo -e "${GREEN}Done!${NC}"
