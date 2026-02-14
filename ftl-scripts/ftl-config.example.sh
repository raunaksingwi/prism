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

# Claude API Key (for analysis)
export ANTHROPIC_API_KEY="sk-ant-api03-..."

# Quick run command
alias ftl-run='./run-ftl-local.sh --service-account-key "$FTL_SERVICE_ACCOUNT_KEY" --phone "$FTL_TEST_PHONE" --otp "$FTL_TEST_OTP"'
alias ftl-analyze='./run-ftl-local.sh --service-account-key "$FTL_SERVICE_ACCOUNT_KEY" --phone "$FTL_TEST_PHONE" --otp "$FTL_TEST_OTP" --analyze'
alias ftl-quick='./run-ftl-local.sh --service-account-key "$FTL_SERVICE_ACCOUNT_KEY" --phone "$FTL_TEST_PHONE" --otp "$FTL_TEST_OTP" --skip-build'
