# Prism

Automated localization drift detector for mobile and web apps. Prism compares screenshots across locales using Gemini vision to catch text truncation, layout shifts, untranslated strings, RTL issues, and other localization bugs before your users do.

## What It Detects

- **Text truncation** — translated text cut off where the source fits
- **Text overflow/overlap** — strings spilling out of containers
- **Layout shift** — elements repositioned due to string length changes
- **Untranslated strings** — text still in the source language
- **Clipped elements** — buttons/icons cropped by text expansion
- **RTL issues** — mirroring or directionality problems
- **Missing content** — UI elements present in source but absent in target

## Quick Start

### 1. Install

```bash
# Clone the repo
git clone https://github.com/raunaksingwi/prism.git
cd prism

# Install dependencies (requires Python 3.12+)
uv sync

# Install Playwright browsers (needed for web crawling)
uv run playwright install chromium
```

### 2. Set your API key

```bash
# Create a .env file (or export directly)
echo 'GEMINI_API_KEY=your-key-here' > .env
```

Get a Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey).

### 3. Run

Prism has three modes: **compare two screenshots**, **crawl a website**, or **analyze Firebase Test Lab results**.

## Usage

### Compare Two Screenshots

Compare a source (original language) screenshot against a target (localized) screenshot:

```bash
uv run python main.py analyze source_en.png target_fr.png
```

Output is plain text — one actionable fix per line:

```
- Header: text truncated after "Paramètr..." → increase max-width or use ellipsis
- Submit button: label "Soumettre" overflows container → reduce font-size or abbreviate
```

If no issues are found: `No localization issues detected.`

### Crawl a Website

Automatically crawl a website, screenshot every page in each locale, and compare:

```bash
uv run python main.py crawl https://example.com en fr es de
```

Arguments:
| Position | Description |
|----------|-------------|
| 1 | Base URL of the site |
| 2 | Source locale (path prefix, e.g. `en`) |
| 3+ | One or more target locales to compare |

The crawler uses BFS to discover pages from the source locale, then screenshots and analyzes each page in every target locale. Results are printed as a grouped drift report.

Options:
- Crawls up to 20 pages by default (configurable via `max_pages` parameter in code)
- Screenshots are saved to a temp directory (path printed at start)

### Analyze Firebase Test Lab Screenshots

If you run your Android app through [Firebase Test Lab](https://firebase.google.com/docs/test-lab) across multiple locales, Prism can compare the resulting screenshots:

```bash
uv run python main.py ftl-analyze /path/to/screenshots en fr es
```

Arguments:
| Position | Description |
|----------|-------------|
| 1 | Path to the FTL screenshots directory |
| 2 | Source locale code (e.g. `en`) |
| 3+ | One or more target locale codes to compare |

FTL organizes screenshots into directories like `starlte-29-en-portrait/`. Prism groups these by device, matches screenshots by filename across locales, and runs drift detection on each pair.

Example output:

```
============================================================
FTL LOCALIZATION DRIFT REPORT
============================================================
Issues found: 2

--- Device: starlte-29-portrait ---

  Locale: fr
  File: screen_001.png
    - Navigation menu: "Paramètres" truncated → increase button width

  Locale: es
  File: screen_003.png
    - Submit button: "Enviar formulario" overflows → use shorter copy or flexible layout

============================================================
```

## Firebase Test Lab Integration

For full FTL automation (build APK, run tests across locales, download screenshots, analyze), see [`ftl-scripts/`](ftl-scripts/README.md).

### Single-command multi-locale test + analysis

```bash
./ftl-scripts/run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --analyze \
  --locales en,hi
```

The first locale is the source; the rest are compared against it.

### Multilingual test runner

For more control over devices and locales, use the dedicated multilingual runner:

```bash
./ftl-scripts/run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,hi,es \
  --devices "redfin,version=30;husky,version=34"
```

**Options:**
- `--service-account-key` — GCP service account JSON key (required)
- `--phone` — Test phone number (required)
- `--otp` — Test OTP code (required)
- `--locales` — Comma-separated locales (default: en,hi)
- `--devices` — Custom device list (default: 3 devices)
- `--apk-path` — Path to APK (default: auto-detect sample-app)
- `--skip-build` — Skip APK build
- `--analyze` — Run Prism analysis (requires `GEMINI_API_KEY`)

## Sample App

A minimal Android app with English and Hindi support is included for testing the FTL scripts. See [`sample-app/README.md`](sample-app/README.md) for details.

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

### Adding more languages

1. Create values folder: `sample-app/app/src/main/res/values-<locale>/`
2. Copy `strings.xml` to the new folder
3. Translate all string values
4. Test with FTL: `--locales en,hi,<locale>`

## Use Cases

### RTL Layout Testing

```bash
./ftl-scripts/run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,ar,he
```

### Screenshot Generation for App Store

```bash
./ftl-scripts/run-ftl-multilang.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --locales en,es,fr,de,it,pt \
  --devices "redfin,version=30"
```

### CI/CD Integration

```yaml
- name: Run FTL Multilingual Tests
  run: |
    ftl-scripts/run-ftl-multilang.sh \
      --service-account-key <(echo "${{ secrets.GCP_KEY }}") \
      --phone ${{ secrets.TEST_PHONE }} \
      --otp ${{ secrets.TEST_OTP }} \
      --locales en,hi,es
```

## Project Structure

```
prism/
├── main.py                          # Core analysis, web crawler, FTL analyzer, CLI
├── test_main.py                     # Test suite
├── pyproject.toml                   # Project config and dependencies
├── .env                             # Your GEMINI_API_KEY (git-ignored)
├── ftl-scripts/                     # Firebase Test Lab scripts
│   ├── run-ftl-local.sh             # FTL runner (supports --locales)
│   ├── run-ftl-multilang.sh         # Multilingual test runner
│   ├── setup-ftl.sh                 # One-time setup
│   ├── ftl-config.example.sh        # Config template
│   ├── README.md                    # Quick start
│   └── FTL_LOCAL_USAGE.md           # Detailed docs
└── sample-app/                      # Sample Android app
    ├── app/src/main/
    │   ├── java/...                 # Kotlin source
    │   └── res/
    │       ├── values/              # English strings
    │       ├── values-hi/           # Hindi strings
    │       └── layout/              # UI layouts
    └── README.md
```

## Requirements

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (package manager)
- `GEMINI_API_KEY` environment variable
- Playwright Chromium (for web crawling only — `uv run playwright install chromium`)
- gcloud CLI (for FTL scripts — `brew install google-cloud-sdk`)
- Java 17+ and Android SDK (for building the sample app)

## Development

```bash
# Run tests
uv run pytest test_main.py -v

# Run tests with coverage
uv run pytest test_main.py -v --cov=main
```

## Cost Optimization

Firebase Test Lab charges per device-hour (~$5/hour physical, ~$1/hour virtual). Tips:
- Use `--skip-build` after first run
- Test fewer devices: `--devices "redfin,version=30"`
- Test fewer locales during development
- Use the free daily quota (10 physical, 5 virtual tests/day)

## How It Works

Prism sends pairs of screenshots (source + target locale) to Gemini's vision model with a carefully tuned prompt that:

1. Treats the source screenshot as **ground truth** — its layout is correct by definition
2. Only flags differences **caused by localization** — not pre-existing design issues
3. Applies a **high visibility threshold** — only reports issues a human would immediately notice at normal viewing distance
4. Outputs **actionable fix instructions** formatted for developers

This means Prism won't flood you with false positives from minor pixel shifts or pre-existing UI quirks. It focuses on the localization bugs that actually matter.
