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
#   --service-account-key <path>  Path to GCP service account JSON key (optional for local)
#   --phone <number>              Test phone number (required for robo tests)
#   --otp <code>                  Test OTP code (required for robo tests)
#   --project-id <id>             GCP project ID (optional, auto-detected)
#   --bucket <name>               GCS bucket name (optional, auto-generated)
#   --locales <list>              Comma-separated locales (default: en,hi)
#   --devices <list>              Comma-separated devices (optional)
#   --apk-path <path>             Path to APK (default: auto-detect)
#   --skip-build                  Skip APK build
#   --no-robo                     Skip robo script (just explore)
#   --analyze                     Run Claude analysis
#   --help                        Show help
#
# Authentication:
#   Uses gcloud auth login (interactive) if no service account key provided.
#   Service account key is recommended for CI/CD.
#
# Examples:
#   # Local testing with gcloud auth
#   ./run-ftl-multilang.sh --locales en,hi --no-robo
#
#   # With robo script
#   ./run-ftl-multilang.sh --phone 9876543210 --otp 123456 --locales en,hi
#
#   # CI/CD with service account
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
NO_ROBO=false
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
    --no-robo) NO_ROBO=true; shift ;;
    --analyze) RUN_ANALYSIS=true; shift ;;
    --help) head -n 40 "$0" | tail -n +3; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

# Validate robo test credentials
if [ "$NO_ROBO" = false ]; then
  if [ -z "$TEST_PHONE" ] || [ -z "$TEST_OTP" ]; then
    echo -e "${YELLOW}Warning: --phone and --otp not provided${NC}"
    echo -e "${YELLOW}Running without robo script (basic exploration only)${NC}"
    NO_ROBO=true
  fi
fi

# Validate service account key if provided
if [ -n "$SERVICE_ACCOUNT_KEY" ] && [ ! -f "$SERVICE_ACCOUNT_KEY" ]; then
  echo -e "${RED}Error: Service account key file not found: $SERVICE_ACCOUNT_KEY${NC}"
  exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check dependencies
echo -e "${BLUE}Checking dependencies...${NC}"
if ! command -v gcloud &> /dev/null; then
  echo -e "${RED}Error: gcloud CLI not found${NC}"
  echo -e "Install: brew install google-cloud-sdk"
  exit 1
fi
echo -e "${GREEN}✓ gcloud CLI found${NC}\n"

# Authenticate with GCP
echo -e "${BLUE}Authenticating with Google Cloud...${NC}"
if [ -n "$SERVICE_ACCOUNT_KEY" ]; then
  # Use service account key (CI/CD mode)
  echo -e "${BLUE}Using service account authentication...${NC}"
  gcloud auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY"

  # Extract project ID from key if not provided
  if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(grep -o '"project_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$SERVICE_ACCOUNT_KEY" | sed 's/"project_id"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
    if [ -z "$PROJECT_ID" ]; then
      echo -e "${RED}Error: Could not extract project_id from service account key${NC}"
      exit 1
    fi
  fi
  gcloud config set project "$PROJECT_ID"
  echo -e "${GREEN}✓ Service account authenticated${NC}"
else
  # Use gcloud auth login (local mode)
  echo -e "${BLUE}Using gcloud user authentication...${NC}"

  # Check if already authenticated
  CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)

  if [ -z "$CURRENT_ACCOUNT" ]; then
    echo -e "${YELLOW}No active gcloud account found${NC}"
    echo -e "${BLUE}Opening browser for authentication...${NC}"
    gcloud auth login
  else
    echo -e "${GREEN}✓ Found account: $CURRENT_ACCOUNT${NC}"

    # Try to validate credentials
    if ! gcloud auth print-access-token &> /dev/null; then
      echo -e "${YELLOW}Credentials expired, re-authenticating...${NC}"
      gcloud auth login
    else
      echo -e "${GREEN}✓ Credentials are valid${NC}"
    fi
  fi

  # Get or set project ID
  if [ -z "$PROJECT_ID" ]; then
    # Try to get current project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

    if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
      echo -e "${YELLOW}No project configured${NC}"
      echo -e "${BLUE}Listing your projects:${NC}\n"
      gcloud projects list --format="table(projectId,name)"
      echo ""
      read -p "Enter project ID to use: " PROJECT_ID

      if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}Error: Project ID required${NC}"
        exit 1
      fi
    fi
  fi

  gcloud config set project "$PROJECT_ID"
  echo -e "${GREEN}✓ User account authenticated${NC}"
fi

echo -e "${GREEN}Project: $PROJECT_ID${NC}\n"

# Enable required APIs
echo -e "${BLUE}Enabling required Google Cloud APIs...${NC}"
echo -e "${YELLOW}This may take a minute...${NC}"

# Enable Firebase Test Lab API
gcloud services enable testing.googleapis.com --project="$PROJECT_ID" 2>&1 | grep -v "WARNING:" || true

# Enable Cloud Tool Results API
gcloud services enable toolresults.googleapis.com --project="$PROJECT_ID" 2>&1 | grep -v "WARNING:" || true

# Enable Cloud Storage API
gcloud services enable storage-api.googleapis.com --project="$PROJECT_ID" 2>&1 | grep -v "WARNING:" || true

echo -e "${GREEN}✓ APIs enabled${NC}\n"

# Generate bucket name
if [ -z "$BUCKET_NAME" ]; then
  BUCKET_NAME="ftl-multilang-$(date +%s)"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Firebase Test Lab Multilingual Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Project Root: $PROJECT_ROOT"
echo -e "GCP Project: $PROJECT_ID"
echo -e "GCS Bucket: $BUCKET_NAME"
echo -e "Locales: $LOCALES"
echo -e "Robo Script: $([ "$NO_ROBO" = true ] && echo "No" || echo "Yes")"
echo -e "${BLUE}========================================${NC}\n"

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

  if [ "$NO_ROBO" = false ]; then
    # Prepare robo script with credentials
    ROBO_SCRIPT_TEMPLATE="$PROJECT_ROOT/sample-app/robo-script.json"
    ROBO_SCRIPT_TEMP="$SCRIPT_DIR/robo-script-$locale.temp.json"

    if [ -f "$ROBO_SCRIPT_TEMPLATE" ]; then
      sed "s/{{TEST_PHONE_NUMBER}}/$TEST_PHONE/g; s/{{TEST_OTP}}/$TEST_OTP/g" \
        "$ROBO_SCRIPT_TEMPLATE" > "$ROBO_SCRIPT_TEMP"

      gcloud firebase test android run \
        --type robo \
        --app "$APK_PATH" \
        --robo-script "$ROBO_SCRIPT_TEMP" \
        --device $DEVICE_LIST \
        --timeout 10m \
        --results-bucket "$BUCKET_NAME" \
        --results-dir "$RESULTS_DIR" \
        --format="json" > "$SCRIPT_DIR/ftl-results-$locale.json" 2>&1 || true

      rm -f "$ROBO_SCRIPT_TEMP"
    else
      echo -e "${YELLOW}No robo script found, running basic robo test${NC}"
      gcloud firebase test android run \
        --type robo \
        --app "$APK_PATH" \
        --device $DEVICE_LIST \
        --timeout 10m \
        --results-bucket "$BUCKET_NAME" \
        --results-dir "$RESULTS_DIR" \
        --format="json" > "$SCRIPT_DIR/ftl-results-$locale.json" 2>&1 || true
    fi
  else
    # Run without robo script (basic exploration)
    gcloud firebase test android run \
      --type robo \
      --app "$APK_PATH" \
      --device $DEVICE_LIST \
      --timeout 10m \
      --results-bucket "$BUCKET_NAME" \
      --results-dir "$RESULTS_DIR" \
      --format="json" > "$SCRIPT_DIR/ftl-results-$locale.json" 2>&1 || true
  fi

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

# Prompt for Gemini API key if not set and multiple locales tested
if [ -z "$GEMINI_API_KEY" ] && [ ${#LOCALE_ARRAY[@]} -gt 1 ]; then
  # Try to load from .env file
  ENV_FILE="$PROJECT_ROOT/.env"
  if [ -f "$ENV_FILE" ]; then
    GEMINI_API_KEY=$(grep "^GEMINI_API_KEY=" "$ENV_FILE" | cut -d '=' -f2- | tr -d '"' | tr -d "'")
    if [ -n "$GEMINI_API_KEY" ]; then
      export GEMINI_API_KEY
      echo -e "${GREEN}✓ Loaded Gemini API key from .env${NC}\n"
    fi
  fi
fi

# Prompt for Gemini API key if still not set
if [ -z "$GEMINI_API_KEY" ] && [ ${#LOCALE_ARRAY[@]} -gt 1 ]; then
  echo -e "${YELLOW}Gemini API key not found${NC}"
  echo -e "${BLUE}Would you like to run AI-powered localization drift analysis?${NC}"
  echo -e "Get a free API key from: ${BLUE}https://aistudio.google.com/apikey${NC}"
  echo ""
  read -p "Enter Gemini API key (or press Enter to skip): " USER_GEMINI_KEY

  if [ -n "$USER_GEMINI_KEY" ]; then
    export GEMINI_API_KEY="$USER_GEMINI_KEY"
    echo -e "${GREEN}✓ API key set${NC}"

    # Ask to save for future use
    read -p "Save API key to .env for future use? (y/N): " SAVE_KEY
    if [[ "$SAVE_KEY" =~ ^[Yy]$ ]]; then
      ENV_FILE="$PROJECT_ROOT/.env"
      if grep -q "^GEMINI_API_KEY=" "$ENV_FILE" 2>/dev/null; then
        # Update existing key
        sed -i.bak "s/^GEMINI_API_KEY=.*/GEMINI_API_KEY=\"$USER_GEMINI_KEY\"/" "$ENV_FILE"
        rm -f "$ENV_FILE.bak"
      else
        # Add new key
        echo "GEMINI_API_KEY=\"$USER_GEMINI_KEY\"" >> "$ENV_FILE"
      fi
      echo -e "${GREEN}✓ API key saved to $ENV_FILE${NC}\n"
    else
      echo ""
    fi
  else
    echo -e "${YELLOW}Skipping analysis${NC}\n"
  fi
fi

# Run Prism localization analysis if GEMINI_API_KEY is set and multiple locales tested
if [ -n "$GEMINI_API_KEY" ] && [ ${#LOCALE_ARRAY[@]} -gt 1 ]; then
  echo -e "${BLUE}Running Prism localization analysis...${NC}"

  # Determine source locale (first in list) and target locales (rest)
  SOURCE_LOCALE="${LOCALE_ARRAY[0]}"
  TARGET_LOCALES=("${LOCALE_ARRAY[@]:1}")

  echo -e "${YELLOW}Source locale: $SOURCE_LOCALE${NC}"
  echo -e "${YELLOW}Target locales: ${TARGET_LOCALES[*]}${NC}\n"

  # Run Python analysis
  cd "$PROJECT_ROOT"
  if command -v python3 &> /dev/null; then
    python3 main.py ftl-analyze "$SCREENSHOTS_BASE" "$SOURCE_LOCALE" "${TARGET_LOCALES[@]}" 2>&1 || {
      echo -e "${YELLOW}Warning: Prism analysis failed${NC}"
    }
  else
    echo -e "${YELLOW}Warning: python3 not found, skipping Prism analysis${NC}"
  fi

  echo ""
elif [ ${#LOCALE_ARRAY[@]} -gt 1 ]; then
  echo -e "${YELLOW}Tip: Set GEMINI_API_KEY to enable automatic localization drift analysis${NC}"
  echo -e "${YELLOW}Run manually: python3 main.py ftl-analyze $SCREENSHOTS_BASE ${LOCALE_ARRAY[0]} ${LOCALE_ARRAY[@]:1}${NC}\n"
fi

# Open screenshots folder (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo -e "${BLUE}Opening screenshots folder...${NC}"
  open "$SCREENSHOTS_BASE"
fi

echo -e "${GREEN}Done!${NC}"
