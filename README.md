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

```bash
# One-command multi-locale test + analysis
./ftl-scripts/run-ftl-local.sh \
  --service-account-key ~/gcp-key.json \
  --phone 9876543210 \
  --otp 123456 \
  --analyze \
  --locales en,fr,es
```

The first locale is the source; the rest are compared against it.

## Project Structure

```
prism/
├── main.py              # Core analysis, web crawler, FTL analyzer, CLI
├── test_main.py         # Test suite
├── pyproject.toml       # Project config and dependencies
├── .env                 # Your GEMINI_API_KEY (git-ignored)
└── ftl-scripts/         # Firebase Test Lab automation
    ├── run-ftl-local.sh       # Main FTL runner (supports --locales)
    ├── setup-ftl.sh           # One-time setup for FTL
    ├── ftl-config.example.sh  # Config template
    ├── FTL_LOCAL_USAGE.md     # Detailed FTL usage guide
    └── README.md              # FTL scripts overview
```

## Requirements

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (package manager)
- `GEMINI_API_KEY` environment variable
- Playwright Chromium (for web crawling only — `uv run playwright install chromium`)

## Development

```bash
# Run tests
uv run pytest test_main.py -v

# Run tests with coverage
uv run pytest test_main.py -v --cov=main
```

## How It Works

Prism sends pairs of screenshots (source + target locale) to Gemini's vision model with a carefully tuned prompt that:

1. Treats the source screenshot as **ground truth** — its layout is correct by definition
2. Only flags differences **caused by localization** — not pre-existing design issues
3. Applies a **high visibility threshold** — only reports issues a human would immediately notice at normal viewing distance
4. Outputs **actionable fix instructions** formatted for developers

This means Prism won't flood you with false positives from minor pixel shifts or pre-existing UI quirks. It focuses on the localization bugs that actually matter.
