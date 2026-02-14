# Prism - Firebase Test Lab Multilingual Testing Suite

Automated testing toolkit for running Firebase Test Lab tests across multiple languages and organizing screenshots by locale.

## Contents

- **[ftl-scripts/](ftl-scripts/)** - Firebase Test Lab runner scripts
- **[sample-app/](sample-app/)** - Sample Android app with multilingual support

## Quick Start

### 1. Setup Environment

```bash
cd ftl-scripts
./setup-ftl.sh
```

### 2. Test the Sample App

```bash
# Build the sample app
cd sample-app
./gradlew assembleDebug

# Run FTL tests in English and Hindi
cd ../ftl-scripts
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,hi
```

### 3. View Results

Screenshots will be organized by language:

```
ftl-scripts/screenshots/20260214_153045/
├── en/
│   ├── starlte-29-en-portrait/
│   ├── redfin-30-en-portrait/
│   └── husky-34-en-portrait/
└── hi/
    ├── starlte-29-hi-portrait/
    ├── redfin-30-hi-portrait/
    └── husky-34-hi-portrait/
```

## Features

### Multilingual Testing

- Test your app across multiple locales in a single run
- Automatically organizes screenshots by language
- Supports all Android locales (en, hi, es, fr, de, etc.)
- Easy comparison of UI across languages

### Sample App Included

- Pre-built Android app with English and Hindi support
- Material Design UI components
- Simple name input and greeting flow
- Perfect for testing the FTL scripts
- Easily customizable for your needs

### Automated FTL Execution

- Auto-creates GCS buckets if needed
- Handles GCP authentication
- Builds APK or uses existing one
- Downloads and organizes all screenshots
- Comprehensive logging and error handling

## Scripts

### run-ftl-multilang.sh

Runs Firebase Test Lab tests across multiple locales.

```bash
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,hi,es \
  --devices "starlte,version=29;redfin,version=30" \
  --apk-path /path/to/app.apk
```

**Options:**
- `--service-account-key` - GCP service account JSON key (required)
- `--phone` - Test phone number (required)
- `--otp` - Test OTP code (required)
- `--locales` - Comma-separated locales (default: en,hi)
- `--devices` - Custom device list (default: 3 devices)
- `--apk-path` - Path to APK (default: auto-detect sample-app)
- `--skip-build` - Skip APK build
- `--analyze` - Run Claude analysis (requires ANTHROPIC_API_KEY)

### run-ftl-local.sh

Single-locale FTL runner (original script).

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456
```

### setup-ftl.sh

One-time setup script for dependencies and configuration.

```bash
./setup-ftl.sh
```

## Sample App

A minimal Android app demonstrating multilingual support.

### Features

- **English and Hindi** string resources
- Simple name input form
- Personalized greeting display
- Feature list with icons
- Material Design components

### Building

```bash
cd sample-app
./gradlew assembleDebug
```

APK output: `app/build/outputs/apk/debug/app-debug.apk`

### Adding More Languages

1. Create values folder: `app/src/main/res/values-<locale>/`
2. Copy `strings.xml` to the new folder
3. Translate all string values
4. Test with FTL: `--locales en,hi,<locale>`

Example for Spanish:
```bash
mkdir -p app/src/main/res/values-es/
cp app/src/main/res/values/strings.xml app/src/main/res/values-es/
# Edit values-es/strings.xml with Spanish translations
```

## Requirements

- **gcloud CLI**: `brew install google-cloud-sdk`
- **Java 17+**: For building Android apps
- **Android SDK**: API 35 (or modify build.gradle)
- **GCP Service Account**: With Firebase Test Lab Admin + Storage Admin roles
- **Node.js** (optional): For Claude analysis

## Cost Optimization

Firebase Test Lab charges per device-hour:
- Physical devices: ~$5/hour
- Virtual devices: ~$1/hour

### Tips to Reduce Costs

1. **Use fewer devices**:
   ```bash
   --devices "redfin,version=30"  # Just one device
   ```

2. **Test specific locales**:
   ```bash
   --locales en,hi  # Only 2 languages instead of 5
   ```

3. **Skip build when iterating**:
   ```bash
   --skip-build  # Reuse existing APK
   ```

4. **Use default free quota**:
   - 10 tests/day on physical devices
   - 5 tests/day on virtual devices

## Use Cases

### 1. Multilingual App Testing

Test how your app looks in different languages without manually changing device settings.

```bash
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,hi,es,fr,de \
  --apk-path /path/to/your/app.apk
```

### 2. RTL Layout Testing

Test right-to-left languages (Arabic, Hebrew):

```bash
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,ar,he
```

### 3. Screenshot Generation

Generate localized screenshots for app store listings:

```bash
# Generate screenshots for Play Store
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,es,fr,de,it,pt \
  --devices "redfin,version=30"  # Single high-quality device
```

### 4. CI/CD Integration

Add to your GitHub Actions workflow:

```yaml
- name: Run FTL Multilingual Tests
  run: |
    ftl-scripts/run-ftl-multilang.sh \
      --service-account-key <(echo "${{ secrets.GCP_KEY }}") \
      --phone ${{ secrets.TEST_PHONE }} \
      --otp ${{ secrets.TEST_OTP }} \
      --locales en,hi,es
```

## Documentation

- **[ftl-scripts/README.md](ftl-scripts/README.md)** - Quick start guide for FTL scripts
- **[ftl-scripts/FTL_LOCAL_USAGE.md](ftl-scripts/FTL_LOCAL_USAGE.md)** - Detailed usage documentation
- **[sample-app/README.md](sample-app/README.md)** - Sample app documentation

## Troubleshooting

### "gcloud not found"

```bash
brew install google-cloud-sdk
```

### "SDK location not found"

Create `sample-app/local.properties`:
```properties
sdk.dir=/Users/YOUR_USERNAME/Library/Android/sdk
```

### "Permission denied"

```bash
chmod +x ftl-scripts/*.sh
```

### "No screenshots found"

Check GCS bucket manually:
```bash
gsutil ls gs://YOUR_BUCKET_NAME/
```

### APK build fails

```bash
cd sample-app
./gradlew clean
./gradlew assembleDebug --stacktrace
```

## Examples

### Test 3 Languages on 2 Devices

```bash
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,hi,es \
  --devices "redfin,version=30;husky,version=34"
```

Result: 6 test runs (3 locales × 2 devices)

### Use Custom APK

```bash
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,hi \
  --apk-path /path/to/custom-app.apk \
  --skip-build
```

### Generate Bucket Name

```bash
./run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,hi
  # Bucket name auto-generated: bhume-ftl-multilang-<timestamp>
```

## Project Structure

```
prism/
├── ftl-scripts/                      # Firebase Test Lab scripts
│   ├── run-ftl-multilang.sh          # Multilingual test runner
│   ├── run-ftl-local.sh              # Single-locale runner
│   ├── setup-ftl.sh                  # One-time setup
│   ├── ftl-config.example.sh         # Config template
│   ├── README.md                     # Quick start
│   └── FTL_LOCAL_USAGE.md            # Detailed docs
│
├── sample-app/                       # Sample Android app
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── java/...              # Kotlin source
│   │   │   └── res/
│   │   │       ├── values/           # English strings
│   │   │       ├── values-hi/        # Hindi strings
│   │   │       └── layout/           # UI layouts
│   │   └── build.gradle
│   ├── build.gradle
│   ├── settings.gradle
│   ├── gradlew
│   └── README.md
│
└── README.md                         # This file
```

## Contributing

Feel free to:
- Add more language support to sample app
- Improve FTL scripts
- Add more example use cases
- Report issues or bugs

## License

Open source - use as you wish.

## Credits

Created with Claude Sonnet 4.5
