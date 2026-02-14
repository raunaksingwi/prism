# Firebase Test Lab Scripts

Local scripts for running Firebase Test Lab robo tests and analyzing screenshots.

## Quick Start

```bash
# 1. Run setup
cd testing/scripts
./setup-ftl.sh

# 2. Configure your credentials
cp ftl-config.example.sh ftl-config.sh
nano ftl-config.sh  # Edit with your values

# 3. Source the config
source ftl-config.sh

# 4. Run tests
ftl-run              # Build and test
ftl-quick            # Test without rebuilding
ftl-analyze          # Test with Claude analysis
```

## What's Included

### Main Scripts

1. **run-ftl-local.sh** - Main script that runs Firebase Test Lab tests locally
   - Builds APK
   - Runs robo tests on 7 devices (Android 10-16)
   - Downloads screenshots
   - Optional Claude analysis

2. **setup-ftl.sh** - One-time setup script
   - Checks dependencies
   - Enables GCP APIs
   - Creates config template
   - Sets up aliases

3. **analyze-screenshots.js** - Claude-powered screenshot analysis
   - Detects UI issues
   - Generates structured report
   - Called automatically by run-ftl-local.sh with --analyze flag

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

2. **GCP Service Account Key** with roles:
   - Firebase Test Lab Admin
   - Storage Admin

3. **Test credentials**:
   - Phone number
   - OTP code

4. **Optional**: Anthropic API key (for `--analyze` flag)

## Usage Examples

### Basic Run

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456
```

### With Analysis

```bash
export ANTHROPIC_API_KEY="sk-ant-..."

./run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --analyze
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
│   └── 20260214_153045/          # Timestamp folder
│       ├── starlte-29-en-portrait/
│       ├── redfin-30-en-portrait/
│       └── ...
└── scripts/
    ├── ftl-results.json          # FTL execution logs
    └── analysis-report.json      # Claude analysis (if --analyze)
```

## Configuration with Aliases

After setting up ftl-config.sh, you get convenient aliases:

```bash
ftl-run          # Full build + test
ftl-quick        # Skip build, reuse APK
ftl-analyze      # Build + test + Claude analysis
```

Add these permanently by adding this line to your `~/.zshrc` or `~/.bashrc`:

```bash
source /path/to/BhuMeApp/testing/scripts/ftl-config.sh
```

## Cost Optimization

Each test run costs ~$9 (7 devices × 15 min × $5/hour).

To reduce costs:
- Use `--skip-build` after first run
- Remove unnecessary devices from run-ftl-local.sh
- Test on fewer devices during development

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "gcloud not found" | Install gcloud CLI: `brew install google-cloud-sdk` |
| "Permission denied" | Make script executable: `chmod +x run-ftl-local.sh` |
| "Bucket creation failed" | Check service account has Storage Admin role |
| "No screenshots found" | Check GCS manually: `gsutil ls gs://BUCKET_NAME/` |
| APK build fails | Clean first: `cd android && ./gradlew clean` |
| Analysis fails | Check `ANTHROPIC_API_KEY` is set |

## Advanced Usage

### Custom Project ID

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --project-id my-custom-project
```

### Custom Bucket

```bash
./run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --bucket my-ftl-results-bucket
```

### Manual Analysis

```bash
export SCREENSHOTS_DIR=/path/to/screenshots
export ANTHROPIC_API_KEY="sk-ant-..."

node analyze-screenshots.js
```

## Integration with GitHub Actions

The scripts are compatible with the existing GitHub Actions workflow in `.github/workflows/ui-tests.yml`.

The workflow uses the same logic but runs in CI/CD context.

## Help

For detailed help:
```bash
./run-ftl-local.sh --help
cat FTL_LOCAL_USAGE.md
```

For issues with the scripts:
- Check logs in `ftl-results.json`
- View GCS bucket: `gsutil ls gs://BUCKET_NAME/`
- Check gcloud config: `gcloud config list`

## File Structure

```
testing/scripts/
├── run-ftl-local.sh          # Main test runner script
├── setup-ftl.sh              # One-time setup script
├── analyze-screenshots.js     # Claude analysis script
├── package.json              # Node dependencies for analysis
├── ftl-config.example.sh     # Config template
├── ftl-config.sh             # Your config (git-ignored)
├── FTL_LOCAL_USAGE.md        # Detailed usage guide
├── README.md                 # This file
├── ftl-results.json          # FTL logs (generated)
└── analysis-report.json      # Analysis report (generated)
```

## Support

For questions or issues:
1. Check FTL_LOCAL_USAGE.md for detailed documentation
2. Review Firebase Console: https://console.firebase.google.com/
3. Check GCS bucket for raw results
4. View logs in ftl-results.json
