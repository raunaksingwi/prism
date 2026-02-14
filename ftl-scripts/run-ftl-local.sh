#!/bin/bash

###############################################################################
# Firebase Test Lab Local Runner
#
# This script runs Firebase Test Lab robo tests locally and downloads screenshots.
# It handles GCP authentication, bucket creation, APK building, and analysis.
#
# Usage:
#   ./run-ftl-local.sh [options]
#
# Options:
#   --service-account-key <path>  Path to GCP service account JSON key (required)
#   --phone <number>              Test phone number (required)
#   --otp <code>                  Test OTP code (required)
#   --project-id <id>             GCP project ID (optional, read from key if not provided)
#   --bucket <name>               GCS bucket name (optional, auto-generated if not provided)
#   --skip-build                  Skip APK build (use existing APK)
#   --analyze                     Run Claude analysis after tests
#   --help                        Show this help message
#
# Example:
#   ./run-ftl-local.sh \
#     --service-account-key ~/gcp-key.json \
#     --phone 9876543210 \
#     --otp 123456 \
#     --analyze
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SKIP_BUILD=false
RUN_ANALYSIS=false
SERVICE_ACCOUNT_KEY=""
TEST_PHONE=""
TEST_OTP=""
PROJECT_ID=""
BUCKET_NAME=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --service-account-key)
      SERVICE_ACCOUNT_KEY="$2"
      shift 2
      ;;
    --phone)
      TEST_PHONE="$2"
      shift 2
      ;;
    --otp)
      TEST_OTP="$2"
      shift 2
      ;;
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --bucket)
      BUCKET_NAME="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --analyze)
      RUN_ANALYSIS=true
      shift
      ;;
    --help)
      head -n 30 "$0" | tail -n +3
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [ -z "$SERVICE_ACCOUNT_KEY" ]; then
  echo -e "${RED}Error: --service-account-key is required${NC}"
  exit 1
fi

if [ ! -f "$SERVICE_ACCOUNT_KEY" ]; then
  echo -e "${RED}Error: Service account key file not found: $SERVICE_ACCOUNT_KEY${NC}"
  exit 1
fi

if [ -z "$TEST_PHONE" ]; then
  echo -e "${RED}Error: --phone is required${NC}"
  exit 1
fi

if [ -z "$TEST_OTP" ]; then
  echo -e "${RED}Error: --otp is required${NC}"
  exit 1
fi

# Get project ID from service account key if not provided
if [ -z "$PROJECT_ID" ]; then
  echo -e "${BLUE}Extracting project ID from service account key...${NC}"
  PROJECT_ID=$(grep -o '"project_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$SERVICE_ACCOUNT_KEY" | sed 's/"project_id"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')

  if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: Could not extract project_id from service account key${NC}"
    exit 1
  fi
  echo -e "${GREEN}Found project ID: $PROJECT_ID${NC}"
fi

# Generate bucket name if not provided
if [ -z "$BUCKET_NAME" ]; then
  BUCKET_NAME="bhume-ftl-results-$(date +%s)"
  echo -e "${YELLOW}No bucket specified, using: $BUCKET_NAME${NC}"
fi

# Timestamp for results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="ftl-results-$TIMESTAMP"

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Firebase Test Lab Local Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Project Root: $PROJECT_ROOT"
echo -e "Service Account: $SERVICE_ACCOUNT_KEY"
echo -e "GCP Project: $PROJECT_ID"
echo -e "GCS Bucket: $BUCKET_NAME"
echo -e "Results Dir: $RESULTS_DIR"
echo -e "${BLUE}========================================${NC}\n"

# Check dependencies
echo -e "${BLUE}Checking dependencies...${NC}"

if ! command -v gcloud &> /dev/null; then
  echo -e "${RED}Error: gcloud CLI not found${NC}"
  echo -e "Install from: https://cloud.google.com/sdk/docs/install"
  exit 1
fi

if ! command -v node &> /dev/null; then
  echo -e "${YELLOW}Warning: node not found, analysis will be skipped${NC}"
  RUN_ANALYSIS=false
fi

if [ "$SKIP_BUILD" = false ]; then
  if [ ! -f "$PROJECT_ROOT/android/gradlew" ]; then
    echo -e "${RED}Error: gradlew not found in $PROJECT_ROOT/android/${NC}"
    exit 1
  fi
fi

echo -e "${GREEN}✓ All dependencies found${NC}\n"

# Authenticate with GCP
echo -e "${BLUE}Authenticating with Google Cloud...${NC}"
gcloud auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY"
gcloud config set project "$PROJECT_ID"
echo -e "${GREEN}✓ Authenticated${NC}\n"

# Check if bucket exists, create if not
echo -e "${BLUE}Checking GCS bucket...${NC}"
if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
  echo -e "${GREEN}✓ Bucket exists: $BUCKET_NAME${NC}\n"
else
  echo -e "${YELLOW}Bucket does not exist, creating...${NC}"
  gsutil mb -p "$PROJECT_ID" "gs://$BUCKET_NAME"
  echo -e "${GREEN}✓ Bucket created: $BUCKET_NAME${NC}\n"
fi

# Build APK if needed
APK_PATH="$PROJECT_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"

if [ "$SKIP_BUILD" = false ]; then
  echo -e "${BLUE}Building APK...${NC}"
  cd "$PROJECT_ROOT"

  # Install dependencies if node_modules doesn't exist
  if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}Installing npm dependencies...${NC}"
    npm ci --legacy-peer-deps
  fi

  cd "$PROJECT_ROOT/android"

  # Clean and build
  ./gradlew clean
  ORG_GRADLE_PROJECT_reactNativeArchitectures=arm64-v8a ./gradlew assembleDebug \
    --no-daemon \
    --parallel \
    --max-workers=4 \
    --build-cache \
    -x lint

  echo -e "${GREEN}✓ APK built successfully${NC}\n"
else
  echo -e "${YELLOW}Skipping build (--skip-build flag)${NC}\n"
fi

# Check if APK exists
if [ ! -f "$APK_PATH" ]; then
  echo -e "${RED}Error: APK not found at $APK_PATH${NC}"
  exit 1
fi

echo -e "${GREEN}✓ APK found: $APK_PATH${NC}\n"

# Prepare robo script with credentials
ROBO_SCRIPT_TEMPLATE="$PROJECT_ROOT/testing/robo-scripts/login-flow.json"
ROBO_SCRIPT_TEMP="$PROJECT_ROOT/testing/robo-scripts/login-flow.temp.json"

if [ ! -f "$ROBO_SCRIPT_TEMPLATE" ]; then
  echo -e "${RED}Error: Robo script template not found: $ROBO_SCRIPT_TEMPLATE${NC}"
  exit 1
fi

echo -e "${BLUE}Preparing robo script with credentials...${NC}"
sed "s/{{TEST_PHONE_NUMBER}}/$TEST_PHONE/g; s/{{TEST_OTP}}/$TEST_OTP/g" \
  "$ROBO_SCRIPT_TEMPLATE" > "$ROBO_SCRIPT_TEMP"
echo -e "${GREEN}✓ Robo script prepared${NC}\n"

# Run Firebase Test Lab
echo -e "${BLUE}Running Firebase Test Lab tests...${NC}"
echo -e "${YELLOW}This may take 10-15 minutes...${NC}\n"

gcloud firebase test android run \
  --type robo \
  --app "$APK_PATH" \
  --robo-script "$ROBO_SCRIPT_TEMP" \
  --device model=starlte,version=29,locale=en,orientation=portrait \
  --device model=redfin,version=30,locale=en,orientation=portrait \
  --device model=caprip,version=31,locale=en,orientation=portrait \
  --device model=cheetah,version=33,locale=en,orientation=portrait \
  --device model=husky,version=34,locale=en,orientation=portrait \
  --device model=pa3q,version=35,locale=en,orientation=portrait \
  --device model=a26x,version=36,locale=en,orientation=portrait \
  --timeout 15m \
  --results-bucket "$BUCKET_NAME" \
  --results-dir "$RESULTS_DIR" \
  --format="json" > "$SCRIPT_DIR/ftl-results.json" 2>&1 || true

# Clean up temp robo script
rm -f "$ROBO_SCRIPT_TEMP"

echo -e "${GREEN}✓ Test execution completed${NC}\n"

# Download screenshots
SCREENSHOTS_DIR="$PROJECT_ROOT/testing/screenshots/$TIMESTAMP"
mkdir -p "$SCREENSHOTS_DIR"

echo -e "${BLUE}Downloading screenshots from GCS...${NC}"
gsutil -m cp -r "gs://$BUCKET_NAME/$RESULTS_DIR/" "$SCREENSHOTS_DIR/" 2>/dev/null || {
  echo -e "${YELLOW}Warning: Could not download some results${NC}"
}

# Count screenshots per device
echo -e "\n${BLUE}=== Screenshots Summary ===${NC}"
total_screenshots=0
for device_dir in "$SCREENSHOTS_DIR"/*/ ; do
  if [ -d "$device_dir" ]; then
    device_name=$(basename "$device_dir")
    count=$(find "$device_dir" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    total_screenshots=$((total_screenshots + count))
    echo -e "${GREEN}$device_name: $count screenshots${NC}"
  fi
done
echo -e "${GREEN}Total: $total_screenshots screenshots${NC}\n"

if [ $total_screenshots -eq 0 ]; then
  echo -e "${YELLOW}Warning: No screenshots found${NC}"
  echo -e "Check GCS bucket manually: gs://$BUCKET_NAME/$RESULTS_DIR"
else
  echo -e "${GREEN}✓ Screenshots downloaded to: $SCREENSHOTS_DIR${NC}\n"
fi

# Run analysis if requested
if [ "$RUN_ANALYSIS" = true ] && [ $total_screenshots -gt 0 ]; then
  echo -e "${BLUE}Running Claude analysis...${NC}"

  cd "$SCRIPT_DIR"

  # Install analysis script dependencies if needed
  if [ ! -d "node_modules" ]; then
    npm install
  fi

  # Set environment variables for analysis
  export SCREENSHOTS_DIR="$SCREENSHOTS_DIR"
  export GCS_BUCKET="$BUCKET_NAME"
  export GCS_RESULTS_DIR="$RESULTS_DIR"

  if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo -e "${YELLOW}Warning: ANTHROPIC_API_KEY not set, analysis will be skipped${NC}"
  else
    node analyze-screenshots.js || {
      echo -e "${YELLOW}Warning: Analysis failed, continuing...${NC}"
    }

    if [ -f "analysis-report.json" ]; then
      echo -e "${GREEN}✓ Analysis report saved: $SCRIPT_DIR/analysis-report.json${NC}\n"
    fi
  fi
fi

# Print final summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Test Lab Run Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Results: $SCREENSHOTS_DIR"
echo -e "GCS Path: gs://$BUCKET_NAME/$RESULTS_DIR"
echo -e "FTL JSON: $SCRIPT_DIR/ftl-results.json"

if [ "$RUN_ANALYSIS" = true ] && [ -f "$SCRIPT_DIR/analysis-report.json" ]; then
  echo -e "Analysis: $SCRIPT_DIR/analysis-report.json"
fi

echo -e "${BLUE}========================================${NC}\n"

# Open screenshots folder (macOS only)
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo -e "${BLUE}Opening screenshots folder...${NC}"
  open "$SCREENSHOTS_DIR"
fi

echo -e "${GREEN}Done!${NC}"
