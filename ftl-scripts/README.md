# Firebase Test Lab Scripts

Local scripts for running Firebase Test Lab robo tests across multiple locales and analyzing screenshots for localization drift using Prism.

## Quick Start

```bash
# 1. Run setup
cd ftl-scripts
./setup-ftl.sh

# 2. Configure your credentials
cp ftl-config.example.sh ftl-config.sh
nano ftl-config.sh  # Edit with your values

# 3. Source the config
source ftl-config.sh

# 4. Run tests
ftl-run              # Build and test (single locale)
ftl-quick            # Test without rebuilding
ftl-analyze          # Build + test + Prism analysis (multi-locale)
```

## What's Included

### Main Scripts

1. **run-ftl-local.sh** - Main script that runs Firebase Test Lab tests locally
   - Builds APK
   - Runs robo tests on 7 devices (Android 10-16) across multiple locales
   - Downloads screenshots
   - Optional Prism localization analysis via `--analyze`

2. **setup-ftl.sh** - One-time setup script
   - Checks dependencies (gcloud, Python 3)
   - Enables GCP APIs
   - Creates config template

### Configuration Files

- **ftl-config.example.sh** - Template configuration file
- **ftl-config.sh** - Your actual config (created by you, git-ignored)

### Documentation

- **FTL_LOCAL_USAGE.md** - Detailed usage guide with examples
- **README.md** - This file

## Prerequisites

Before running the scripts, you need:

1. **gcloud CLI** installed
   ```bash
   brew install google-cloud-sdk  # macOS
   ```

2. **Python 3** installed (for Prism analysis)

3. **GCP Service Account Key** with roles:
   - Firebase Test Lab Admin
   - Storage Admin

4. **Test credentials**:
   - Phone number
   - OTP code

5. **Optional**: Gemini API key (for `--analyze` flag)

## Usage Examples

### Basic Run

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456
```

### Multi-Locale with Analysis

```bash
export GEMINI_API_KEY="your-key"

./run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --analyze \
  --locales en,hi
```

### Skip Build (Faster)

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --skip-build
```

## Output

After running tests, you'll find:

```
testing/
├── screenshots/
│   └── 20260214_153045/              # Timestamp folder
│       ├── starlte-29-en-portrait/   # Source locale
│       ├── starlte-29-fr-portrait/   # Target locale
│       ├── redfin-30-en-portrait/
│       ├── redfin-30-fr-portrait/
│       └── ...
└── scripts/
    └── ftl-results.json              # FTL execution logs
```

## Standalone Analysis

You can run Prism analysis on existing FTL screenshots without re-running tests:

```bash
python3 main.py ftl-analyze /path/to/screenshots en fr es
```

## Configuration with Aliases

After setting up ftl-config.sh, you get convenient aliases:

```bash
ftl-run          # Full build + test
ftl-quick        # Skip build, reuse APK
ftl-analyze      # Build + test + Prism multi-locale analysis
```

Add these permanently by adding this line to your `~/.zshrc` or `~/.bashrc`:

```bash
source /path/to/ftl-scripts/ftl-config.sh
```

## Cost Optimization

Each test run costs ~$9 per locale (7 devices × 15 min × $5/hour).

To reduce costs:
- Use `--skip-build` after first run
- Remove unnecessary devices from run-ftl-local.sh
- Test on fewer devices during development
- Test fewer locales during development

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "gcloud not found" | Install gcloud CLI: `brew install google-cloud-sdk` |
| "python3 not found" | Install Python 3: `brew install python` |
| "Permission denied" | Make script executable: `chmod +x run-ftl-local.sh` |
| "Bucket creation failed" | Check service account has Storage Admin role |
| "No screenshots found" | Check GCS manually: `gsutil ls gs://BUCKET_NAME/` |
| APK build fails | Clean first: `cd android && ./gradlew clean` |
| Analysis fails | Check `GEMINI_API_KEY` is set and ≥2 locales specified |

## Help

For detailed help:
```bash
./run-ftl-local.sh --help
cat FTL_LOCAL_USAGE.md
```
