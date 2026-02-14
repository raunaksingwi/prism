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
alias ftl-analyze='./run-ftl-local.sh --service-account-key "$FTL_SERVICE_ACCOUNT_KEY" --phone "$FTL_TEST_PHONE" --otp "$FTL_TEST_OTP" --analyze --locales en,fr,es'
alias ftl-quick='./run-ftl-local.sh --service-account-key "$FTL_SERVICE_ACCOUNT_KEY" --phone "$FTL_TEST_PHONE" --otp "$FTL_TEST_OTP" --skip-build'
