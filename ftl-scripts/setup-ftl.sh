#!/bin/bash

###############################################################################
# Firebase Test Lab Setup Script
#
# This script helps you set up your environment for running FTL tests locally.
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Firebase Test Lab Setup${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check if gcloud is installed
echo -e "${BLUE}1. Checking gcloud CLI...${NC}"
if command -v gcloud &> /dev/null; then
  GCLOUD_VERSION=$(gcloud version --format="value(core.version)")
  echo -e "${GREEN}✓ gcloud CLI installed (version: $GCLOUD_VERSION)${NC}\n"
else
  echo -e "${YELLOW}✗ gcloud CLI not found${NC}"
  echo -e "Install from: https://cloud.google.com/sdk/docs/install"
  echo -e "\nOn macOS, run:"
  echo -e "  ${BLUE}brew install google-cloud-sdk${NC}\n"
  echo -e "After installation, run this script again.\n"
  exit 1
fi

# Check Python
echo -e "${BLUE}2. Checking Python...${NC}"
if command -v python3 &> /dev/null; then
  PYTHON_VERSION=$(python3 --version)
  echo -e "${GREEN}✓ $PYTHON_VERSION installed${NC}\n"
else
  echo -e "${YELLOW}✗ Python 3 not found${NC}"
  echo -e "Install from: https://www.python.org/\n"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for service account key
echo -e "${BLUE}3. Checking for service account key...${NC}"
read -p "Enter path to your GCP service account key JSON (or press Enter to skip): " KEY_PATH

if [ -n "$KEY_PATH" ]; then
  if [ -f "$KEY_PATH" ]; then
    echo -e "${GREEN}✓ Service account key found${NC}\n"

    # Extract project ID
    PROJECT_ID=$(grep -o '"project_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$KEY_PATH" | sed 's/"project_id"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')

    if [ -n "$PROJECT_ID" ]; then
      echo -e "${GREEN}✓ Project ID: $PROJECT_ID${NC}\n"

      # Enable required APIs
      echo -e "${BLUE}4. Enabling required Google Cloud APIs...${NC}"
      gcloud auth activate-service-account --key-file="$KEY_PATH"
      gcloud config set project "$PROJECT_ID"

      echo -e "Enabling Firebase Test Lab API..."
      gcloud services enable testing.googleapis.com || echo "Already enabled"

      echo -e "Enabling Tool Results API..."
      gcloud services enable toolresults.googleapis.com || echo "Already enabled"

      echo -e "Enabling Storage API..."
      gcloud services enable storage-api.googleapis.com || echo "Already enabled"

      echo -e "${GREEN}✓ APIs enabled${NC}\n"
    else
      echo -e "${YELLOW}Warning: Could not extract project_id from key${NC}\n"
    fi
  else
    echo -e "${YELLOW}✗ File not found: $KEY_PATH${NC}\n"
  fi
else
  echo -e "${YELLOW}Skipped. You can enable APIs manually later.${NC}\n"
fi

# Check for GEMINI_API_KEY
echo -e "${BLUE}5. Checking for Gemini API key...${NC}"
if [ -n "$GEMINI_API_KEY" ]; then
  echo -e "${GREEN}✓ GEMINI_API_KEY is set${NC}\n"
else
  echo -e "${YELLOW}✗ GEMINI_API_KEY not set${NC}"
  echo -e "To use Prism analysis, set it in your shell profile:"
  echo -e "  ${BLUE}export GEMINI_API_KEY=\"your-key-here\"${NC}\n"
fi

# Create example config file
echo -e "${BLUE}6. Creating example configuration...${NC}"
cat > "$SCRIPT_DIR/ftl-config.example.sh" << 'EOF'
#!/bin/bash

# Firebase Test Lab Local Configuration
# Copy this file to ftl-config.sh and fill in your values
# Then run: source ftl-config.sh

# GCP Service Account Key (absolute path)
export FTL_SERVICE_ACCOUNT_KEY="/path/to/your/gcp-key.json"

# Test Credentials
export FTL_TEST_PHONE="9876543210"
export FTL_TEST_OTP="123456"

# GCP Configuration (optional)
export FTL_PROJECT_ID="your-gcp-project-id"
export FTL_BUCKET_NAME="your-bucket-name"

# Gemini API Key (for Prism localization analysis)
export GEMINI_API_KEY="your-gemini-api-key"

# Quick run command
alias ftl-run='./run-ftl-local.sh --service-account-key "$FTL_SERVICE_ACCOUNT_KEY" --phone "$FTL_TEST_PHONE" --otp "$FTL_TEST_OTP"'
alias ftl-analyze='./run-ftl-local.sh --service-account-key "$FTL_SERVICE_ACCOUNT_KEY" --phone "$FTL_TEST_PHONE" --otp "$FTL_TEST_OTP" --analyze --locales en,hi'
alias ftl-quick='./run-ftl-local.sh --service-account-key "$FTL_SERVICE_ACCOUNT_KEY" --phone "$FTL_TEST_PHONE" --otp "$FTL_TEST_OTP" --skip-build'
EOF

echo -e "${GREEN}✓ Example config created: $SCRIPT_DIR/ftl-config.example.sh${NC}\n"

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "Next steps:"
echo -e "1. Copy the example config:"
echo -e "   ${BLUE}cp testing/scripts/ftl-config.example.sh testing/scripts/ftl-config.sh${NC}"
echo -e ""
echo -e "2. Edit the config with your values:"
echo -e "   ${BLUE}nano testing/scripts/ftl-config.sh${NC}"
echo -e ""
echo -e "3. Source the config (or add to ~/.bashrc or ~/.zshrc):"
echo -e "   ${BLUE}source testing/scripts/ftl-config.sh${NC}"
echo -e ""
echo -e "4. Run FTL tests:"
echo -e "   ${BLUE}ftl-run${NC}              # Build and test"
echo -e "   ${BLUE}ftl-quick${NC}            # Test without rebuilding"
echo -e "   ${BLUE}ftl-analyze${NC}          # Test with Claude analysis"
echo -e ""
echo -e "Or run directly:"
echo -e "   ${BLUE}./run-ftl-local.sh --service-account-key ~/gcp-key.json --phone 9876543210 --otp 123456${NC}"
echo -e ""
echo -e "For more help:"
echo -e "   ${BLUE}./run-ftl-local.sh --help${NC}"
echo -e "   ${BLUE}cat FTL_LOCAL_USAGE.md${NC}"
echo -e ""
echo -e "${BLUE}========================================${NC}\n"
