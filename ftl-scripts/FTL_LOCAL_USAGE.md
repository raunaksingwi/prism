# Firebase Test Lab Local Runner - Usage Guide

## Quick Start

```bash
cd ftl-scripts

./run-ftl-local.sh \
  --service-account-key ~/path/to/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --analyze \
  --locales en,hi
```

## Prerequisites

### 1. Install gcloud CLI

**macOS:**
```bash
brew install google-cloud-sdk
```

**Linux:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

**Windows:**
Download from: https://cloud.google.com/sdk/docs/install

### 2. Get GCP Service Account Key

1. Go to [GCP Console](https://console.cloud.google.com/)
2. Navigate to: **IAM & Admin > Service Accounts**
3. Create a new service account or select existing
4. Grant roles:
   - **Firebase Test Lab Admin**
   - **Storage Admin** (for creating buckets)
5. Click **Keys > Add Key > Create New Key**
6. Choose **JSON** format
7. Save the downloaded file securely (e.g., `~/gcp-bhume-key.json`)

### 3. Enable Required APIs

```bash
gcloud services enable \
  testing.googleapis.com \
  toolresults.googleapis.com \
  storage-api.googleapis.com
```

### 4. Python 3

Python 3 is required for localization analysis. Ensure `python3` is on your PATH.

## Command Options

| Option | Required | Description |
|--------|----------|-------------|
| `--service-account-key <path>` | Yes | Path to GCP service account JSON key |
| `--phone <number>` | Yes | Test phone number (digits only) |
| `--otp <code>` | Yes | Test OTP code |
| `--project-id <id>` | No | GCP project ID (auto-detected from key) |
| `--bucket <name>` | No | GCS bucket name (auto-generated if not provided) |
| `--skip-build` | No | Skip APK build (use existing APK) |
| `--analyze` | No | Run Prism localization analysis after tests |
| `--locales <locale,...>` | No | Comma-separated locales to test (default: `en,hi`) |
| `--help` | No | Show help message |

## Usage Examples

### Basic Run (Build + Test)

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-bhume-key.json \
  --phone 9876543210 \
  --otp 123456
```

### Skip Build (Use Existing APK)

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-bhume-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --skip-build
```

### Multi-Locale Test with Analysis

```bash
export GEMINI_API_KEY="your-key"

./run-ftl-local.sh \
  --service-account-key ~/gcp-bhume-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --analyze \
  --locales en,hi
```

The first locale (`en`) is treated as the source. All subsequent locales (`hi`) are compared against it for localization drift.

### Use Custom Bucket

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-bhume-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --bucket my-ftl-results-bucket
```

### Use Specific Project ID

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-bhume-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --project-id my-gcp-project-id
```

## What the Script Does

1. **Validates Dependencies**
   - Checks for `gcloud` CLI
   - Checks for `python3`
   - Verifies service account key exists
   - Validates required arguments

2. **GCP Authentication**
   - Activates service account
   - Sets project ID (from key or argument)
   - Configures gcloud CLI

3. **Bucket Management**
   - Checks if GCS bucket exists
   - Creates bucket if needed
   - Auto-generates bucket name if not provided

4. **APK Build** (unless `--skip-build`)
   - Installs npm dependencies (if needed)
   - Cleans Android build
   - Builds debug APK (arm64-v8a only)

5. **Robo Script Preparation**
   - Copies template robo script
   - Replaces `{{TEST_PHONE_NUMBER}}` with actual phone
   - Replaces `{{TEST_OTP}}` with actual OTP
   - Creates temporary script file

6. **Firebase Test Lab Execution**
   - Loops over each locale in `--locales`
   - Runs robo test on 7 devices (API 29-36) per locale
   - 15-minute timeout per device
   - Saves results to GCS bucket

7. **Screenshot Download**
   - Downloads all screenshots from GCS
   - Saves to `testing/screenshots/<timestamp>/`
   - Organizes by device folder (e.g., `starlte-29-fr-portrait/`)
   - Prints summary count

8. **Prism Localization Analysis** (if `--analyze` flag)
   - Requires `GEMINI_API_KEY` env variable
   - Groups device directories by device key
   - Matches screenshots by filename across locales
   - Uses Gemini to detect localization drift
   - Prints report grouped by device

9. **Summary Report**
   - Prints all result paths
   - Opens screenshots folder (macOS)

## Output Structure

```
testing/
├── screenshots/
│   └── 20260214_153045/                  # Timestamp
│       ├── starlte-29-en-portrait/       # Source locale
│       │   └── *.png
│       ├── starlte-29-fr-portrait/       # Target locale
│       │   └── *.png
│       ├── redfin-30-en-portrait/
│       │   └── *.png
│       ├── redfin-30-fr-portrait/
│       │   └── *.png
│       └── ...
└── scripts/
    └── ftl-results.json                  # FTL execution logs
```

## Troubleshooting

### "gcloud not found"

Install gcloud CLI:
```bash
brew install google-cloud-sdk  # macOS
```

### "Permission denied" when running script

Make it executable:
```bash
chmod +x run-ftl-local.sh
```

### "Could not extract project_id"

Either:
- Use `--project-id` flag explicitly
- Verify service account key JSON has `project_id` field

### "Bucket creation failed"

Check service account has **Storage Admin** role:
```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
  --role="roles/storage.admin"
```

### "No screenshots found"

Check GCS bucket manually:
```bash
gsutil ls gs://BUCKET_NAME/ftl-results-*/
```

### APK build fails

Try cleaning first:
```bash
cd android
./gradlew clean
rm -rf build app/build
```

### Analysis fails

Ensure:
- `GEMINI_API_KEY` is set
- Python 3 is installed
- At least 2 locales are specified with `--locales`

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GEMINI_API_KEY` | Only for `--analyze` | Gemini API key for Prism localization analysis |

## Testing Devices

The script tests on 7 devices covering Android 10-16:

| Device | Model | API Level | Android Version |
|--------|-------|-----------|-----------------|
| starlte | Samsung Galaxy S9 | 29 | Android 10 |
| redfin | Google Pixel 5 | 30 | Android 11 |
| caprip | Motorola Moto G Power | 31 | Android 12 |
| cheetah | Google Pixel 7 Pro | 33 | Android 13 |
| husky | Google Pixel 8 Pro | 34 | Android 14 |
| pa3q | Samsung Galaxy S24 | 35 | Android 15 |
| a26x | Google Pixel 9 Pro | 36 | Android 16 |

## Cost Estimation

Firebase Test Lab pricing (as of 2024):
- **Physical devices**: $5/hour/device
- **Virtual devices**: $1/hour/device

This script uses **physical devices**:
- 7 devices × 15 min × $5/hour × N locales = **~$9 × N per run**

For example, 3 locales = ~$27 per run.

To reduce costs:
- Remove devices you don't need from the script
- Use `--skip-build` for faster iterations
- Use virtual devices (modify `--device` flags)
- Test fewer locales during development

## Tips

1. **Save credentials securely**
   ```bash
   # Add to .gitignore
   echo "*.json" >> .gitignore
   echo "!testing/robo-scripts/*.json" >> .gitignore
   ```

2. **Reuse existing bucket**
   ```bash
   # First run creates bucket
   ./run-ftl-local.sh ... --bucket bhume-ftl-results

   # Subsequent runs reuse it
   ./run-ftl-local.sh ... --bucket bhume-ftl-results
   ```

3. **Skip build for faster iterations**
   ```bash
   # First run: build APK
   ./run-ftl-local.sh ...

   # Subsequent runs: reuse APK
   ./run-ftl-local.sh ... --skip-build
   ```

4. **Check results in GCP Console**
   - Go to: https://console.firebase.google.com/
   - Navigate to: **Test Lab > Test History**
   - View detailed logs, videos, and crash reports

5. **Run analysis separately**
   ```bash
   # Run FTL first, then analyze screenshots later
   python3 main.py ftl-analyze /path/to/screenshots en fr es
   ```

## Integration with CI/CD

You can use this script in CI/CD pipelines:

```yaml
# .github/workflows/ftl-manual.yml
name: Manual FTL Run

on:
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run FTL
        run: |
          ./ftl-scripts/run-ftl-local.sh \
            --service-account-key <(echo "${{ secrets.GCP_SERVICE_ACCOUNT_KEY }}") \
            --phone ${{ secrets.TEST_PHONE_NUMBER }} \
            --otp ${{ secrets.TEST_OTP }} \
            --analyze \
            --locales en,hi
```

## Next Steps

After running tests:
1. Review screenshots in `testing/screenshots/<timestamp>/`
2. Check the Prism drift report output (if `--analyze`)
3. View detailed logs in `ftl-results.json`
4. Check Firebase Console for full test reports

## Support

For issues:
- Check GCS bucket: `gsutil ls gs://BUCKET_NAME/`
- View FTL logs: `cat ftl-scripts/ftl-results.json`
- Check gcloud config: `gcloud config list`
