import os
import sys
import tempfile
from collections import deque
from typing import Optional
from urllib.parse import urlparse

from dotenv import load_dotenv
from google import genai
from PIL import Image
from playwright.sync_api import sync_playwright

load_dotenv()

DEFAULT_PROMPT = """You are a localization drift detector. You are given two screenshots of the same screen in an Android app:

1. **Source screenshot** (first image) — the original language version. Treat this as the GROUND TRUTH. Its layout, spacing, alignment, and visual structure are correct by definition.
2. **Target screenshot** (second image) — the translated/localized version. Your ONLY job is to find where this drifts from the source.

**YOUR SCOPE IS NARROW:**
- You are ONLY looking for differences CAUSED BY the localization/translation.
- If something looks off in the target but the SAME issue exists in the source, it is NOT your concern — ignore it.
- Do NOT give general UI advice, design suggestions, or flag pre-existing issues. The source is perfect. Period.

**IGNORE these (normal during automated UI crawling):**
- Keyboard open/visible, form fields focused, dropdowns open
- Mid-scroll, mid-transition, or loading states
- Keyboard pushing content up

**Flag ONLY these localization-induced drifts:**
1. **Text truncation**: Translated text cut off where the source text fits fully
2. **Text overflow/overlap**: Translated strings spilling out of or overlapping elements that are fine in source
3. **Layout shift**: Elements repositioned, resized, or broken in target compared to source due to string length changes
4. **Untranslated strings**: Text still in the source language that should have been translated
5. **Clipped elements**: Icons, buttons, or images clipped in target but intact in source, caused by text expansion
6. **RTL issues**: Mirroring or directionality problems if target is an RTL language
7. **Missing content**: UI elements or text present in source but absent in target

**THRESHOLD — Only report issues a human would immediately notice.**
- If you have to squint or zoom in to see the difference, do NOT report it.
- Minor spacing or alignment shifts (a few pixels) are NOT issues.
- The drift must be obviously visible at a normal phone viewing distance.
- When in doubt, do NOT flag it. Err heavily on the side of "no issues."

For each drift, output a concise, actionable fix instruction for a coding agent. Format as plain text, one issue per line:

- [Element/area]: [What drifted from source] → [Suggested fix]

If the target faithfully reproduces the source layout (or differences are too minor to matter), respond with: "No localization issues detected."
"""


def analyze_localization(
    source_image_path: str,
    target_image_path: str,
    prompt: Optional[str] = None,
) -> str:
    """Compare source and target app screenshots to find localization issues.

    Args:
        source_image_path: Path to the source language screenshot.
        target_image_path: Path to the target/localized language screenshot.
        prompt: Custom prompt to send to the model. Uses DEFAULT_PROMPT if None.

    Returns:
        Plain text fix-it instructions for a coding agent.
    """
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY environment variable is not set")

    source_image = Image.open(source_image_path)
    target_image = Image.open(target_image_path)

    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        model="gemini-3-flash-preview",
        contents=[source_image, target_image, prompt or DEFAULT_PROMPT],
    )
    return response.text


# ---------------------------------------------------------------------------
# Crawler helpers
# ---------------------------------------------------------------------------


def _strip_locale_prefix(path: str, locale: str) -> str:
    """Remove a locale prefix from a URL path.

    >>> _strip_locale_prefix("/en/about", "en")
    '/about'
    >>> _strip_locale_prefix("/en", "en")
    '/'
    """
    prefix = f"/{locale}"
    if path == prefix:
        return "/"
    if path.startswith(prefix + "/"):
        return path[len(prefix):]
    return path


def _build_locale_url(base_url: str, locale: str, route: str) -> str:
    """Construct a full URL for a given locale and route.

    >>> _build_locale_url("https://example.com", "fr", "/about")
    'https://example.com/fr/about'
    >>> _build_locale_url("https://example.com", "en", "/")
    'https://example.com/en/'
    """
    return f"{base_url.rstrip('/')}/{locale}{route}"


def _safe_filename(route: str) -> str:
    """Convert a route into a safe filename component.

    >>> _safe_filename("/about/team")
    'about_team'
    >>> _safe_filename("/")
    'index'
    """
    cleaned = route.strip("/")
    if not cleaned:
        return "index"
    return cleaned.replace("/", "_")


# ---------------------------------------------------------------------------
# FTL helpers
# ---------------------------------------------------------------------------


def _parse_device_key(dirname: str) -> Optional[tuple[str, str]]:
    """Parse an FTL device directory name into (device_key, locale).

    FTL directories follow the pattern: <model>-<apiLevel>-<locale>-<orientation>
    e.g. "starlte-29-en-portrait" → ("starlte-29-portrait", "en")

    Returns None if the directory name has fewer than 4 parts.
    """
    parts = dirname.split("-")
    if len(parts) < 4:
        return None
    model = parts[0]
    version = parts[1]
    locale = parts[2]
    orientation = "-".join(parts[3:])
    device_key = f"{model}-{version}-{orientation}"
    return device_key, locale


def _group_device_dirs(
    screenshots_dir: str,
) -> dict[str, dict[str, str]]:
    """Group FTL device subdirectories by device key and locale.

    Handles both flat and nested FTL directory structures:
    - Flat: screenshots_dir/device-version-locale-orientation/
    - Nested: screenshots_dir/locale/ftl-results-*/device-version-locale-orientation/

    Returns: {device_key: {locale: dir_path}}
    """
    groups: dict[str, dict[str, str]] = {}

    # First, try flat structure (direct device directories)
    for entry in sorted(os.listdir(screenshots_dir)):
        full_path = os.path.join(screenshots_dir, entry)
        if not os.path.isdir(full_path):
            continue

        parsed = _parse_device_key(entry)
        if parsed is not None:
            device_key, locale = parsed
            groups.setdefault(device_key, {})[locale] = full_path

    # If no devices found, try nested FTL structure (locale/ftl-results-*/device/)
    if not groups:
        for locale_entry in sorted(os.listdir(screenshots_dir)):
            locale_dir = os.path.join(screenshots_dir, locale_entry)
            if not os.path.isdir(locale_dir):
                continue

            # Look for ftl-results-* subdirectories
            for results_entry in sorted(os.listdir(locale_dir)):
                results_dir = os.path.join(locale_dir, results_entry)
                if not os.path.isdir(results_dir):
                    continue

                # Look for device directories
                for device_entry in sorted(os.listdir(results_dir)):
                    device_dir = os.path.join(results_dir, device_entry)
                    if not os.path.isdir(device_dir):
                        continue

                    parsed = _parse_device_key(device_entry)
                    if parsed is not None:
                        device_key, locale = parsed
                        # Use artifacts subdirectory if it exists
                        artifacts_dir = os.path.join(device_dir, "artifacts")
                        if os.path.isdir(artifacts_dir):
                            device_dir = artifacts_dir
                        groups.setdefault(device_key, {})[locale] = device_dir

    return groups


# ---------------------------------------------------------------------------
# FTL analyze
# ---------------------------------------------------------------------------


def ftl_analyze(
    screenshots_dir: str,
    source_locale: str,
    target_locales: list[str],
) -> list[dict]:
    """Analyze FTL screenshots across locales for localization drift.

    Walks the screenshots directory, groups device subdirs by device key,
    then compares matched PNG files between source and target locales
    using analyze_localization().

    Args:
        screenshots_dir: Path to the FTL screenshots root directory.
        source_locale: The source locale code (e.g. "en").
        target_locales: List of target locale codes to compare against.

    Returns:
        List of issue dicts with keys: device, target_locale, filename, analysis.

    Raises:
        FileNotFoundError: If screenshots_dir does not exist.
    """
    if not os.path.isdir(screenshots_dir):
        raise FileNotFoundError(
            f"Screenshots directory not found: {screenshots_dir}"
        )

    groups = _group_device_dirs(screenshots_dir)
    issues: list[dict] = []

    for device_key, locale_dirs in groups.items():
        source_dir = locale_dirs.get(source_locale)
        if source_dir is None:
            continue

        source_pngs = {
            f for f in os.listdir(source_dir) if f.lower().endswith(".png")
        }

        for target_locale in target_locales:
            target_dir = locale_dirs.get(target_locale)
            if target_dir is None:
                continue

            target_pngs = {
                f for f in os.listdir(target_dir) if f.lower().endswith(".png")
            }

            matched = source_pngs & target_pngs
            skipped = (source_pngs | target_pngs) - matched
            if skipped:
                print(
                    f"  [{device_key}/{target_locale}] "
                    f"Skipped {len(skipped)} unmatched file(s)"
                )

            for filename in sorted(matched):
                source_path = os.path.join(source_dir, filename)
                target_path = os.path.join(target_dir, filename)

                analysis = analyze_localization(source_path, target_path)

                if "no localization issues" not in analysis.lower():
                    issues.append({
                        "device": device_key,
                        "target_locale": target_locale,
                        "filename": filename,
                        "analysis": analysis,
                    })

    return issues


def _extract_same_domain_links(page, base_url: str) -> set[str]:
    """Extract all same-domain links from the page, normalized to paths without query/fragment."""
    parsed_base = urlparse(base_url)
    base_domain = parsed_base.netloc

    hrefs = page.eval_on_selector_all("a[href]", "els => els.map(e => e.href)")

    paths = set()
    for href in hrefs:
        parsed = urlparse(href)
        if parsed.netloc and parsed.netloc != base_domain:
            continue
        path = parsed.path or "/"
        # Normalize: ensure leading slash, strip trailing slash (except root)
        if not path.startswith("/"):
            path = "/" + path
        if path != "/" and path.endswith("/"):
            path = path.rstrip("/")
        paths.add(path)
    return paths


# ---------------------------------------------------------------------------
# Main crawler
# ---------------------------------------------------------------------------


def crawl_and_analyze(
    base_url: str,
    source_locale: str,
    target_locales: list[str],
    max_pages: int = 20,
) -> tuple[list[dict], int]:
    """Crawl a website across locales and compare screenshots for localization drift.

    Uses BFS starting from '/' to discover pages via the source locale, then
    screenshots each page in every target locale and runs analyze_localization().

    Args:
        base_url: The site root (e.g. "https://example.com").
        source_locale: The source locale path prefix (e.g. "en").
        target_locales: List of target locale prefixes (e.g. ["fr", "es"]).
        max_pages: Maximum number of routes to crawl.

    Returns:
        A tuple of (issues_list, pages_crawled_count) where issues_list contains
        dicts with keys: route, target_locale, analysis.
    """
    issues: list[dict] = []
    visited: set[str] = set()
    queue: deque[str] = deque(["/"])
    pages_crawled = 0
    screenshot_dir = tempfile.mkdtemp(prefix="prism_")

    print(f"Screenshots will be saved to: {screenshot_dir}")

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page()

        while queue and pages_crawled < max_pages:
            route = queue.popleft()
            if route in visited:
                continue
            visited.add(route)
            pages_crawled += 1

            # --- Source locale screenshot ---
            source_url = _build_locale_url(base_url, source_locale, route)
            safe_name = _safe_filename(route)
            source_screenshot = os.path.join(
                screenshot_dir, f"{safe_name}_{source_locale}.png"
            )

            print(f"\n[{pages_crawled}/{max_pages}] Crawling route: {route}")
            print(f"  Source: {source_url}")

            try:
                page.goto(source_url, wait_until="networkidle", timeout=30000)
                page.screenshot(path=source_screenshot, full_page=True)
            except Exception as exc:
                print(f"  SKIP (source failed): {exc}")
                continue

            # --- Discover links from source page ---
            raw_links = _extract_same_domain_links(page, base_url)
            for link_path in raw_links:
                normalized = _strip_locale_prefix(link_path, source_locale)
                if normalized not in visited:
                    queue.append(normalized)

            # --- Target locale screenshots + analysis ---
            for target_locale in target_locales:
                target_url = _build_locale_url(base_url, target_locale, route)
                target_screenshot = os.path.join(
                    screenshot_dir, f"{safe_name}_{target_locale}.png"
                )

                print(f"  Target ({target_locale}): {target_url}")

                try:
                    page.goto(target_url, wait_until="networkidle", timeout=30000)
                    page.screenshot(path=target_screenshot, full_page=True)
                except Exception as exc:
                    print(f"  SKIP (target {target_locale} failed): {exc}")
                    continue

                analysis = analyze_localization(source_screenshot, target_screenshot)

                if "no localization issues" not in analysis.lower():
                    issues.append({
                        "route": route,
                        "target_locale": target_locale,
                        "analysis": analysis,
                    })
                    print(f"  Issues found for {target_locale}!")
                else:
                    print(f"  No issues for {target_locale}")

        browser.close()

    return issues, pages_crawled


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


def _print_ftl_report(issues: list[dict]) -> None:
    """Print a summary report of FTL localization issues grouped by device."""
    print("\n" + "=" * 60)
    print("FTL LOCALIZATION DRIFT REPORT")
    print("=" * 60)
    print(f"Issues found: {len(issues)}")

    if not issues:
        print("\nNo localization issues detected across any devices.")
        return

    by_device: dict[str, list[dict]] = {}
    for issue in issues:
        by_device.setdefault(issue["device"], []).append(issue)

    for device, device_issues in by_device.items():
        print(f"\n--- Device: {device} ---")
        for issue in device_issues:
            print(f"\n  Locale: {issue['target_locale']}")
            print(f"  File: {issue['filename']}")
            for line in issue["analysis"].strip().splitlines():
                print(f"    {line}")

    print("\n" + "=" * 60)


def _print_report(issues: list[dict], pages_crawled: int) -> None:
    """Print a summary report of all localization issues found."""
    print("\n" + "=" * 60)
    print("LOCALIZATION DRIFT REPORT")
    print("=" * 60)
    print(f"Pages crawled: {pages_crawled}")
    print(f"Issues found: {len(issues)}")

    if not issues:
        print("\nNo localization issues detected across any pages.")
        return

    # Group by route
    by_route: dict[str, list[dict]] = {}
    for issue in issues:
        by_route.setdefault(issue["route"], []).append(issue)

    for route, route_issues in by_route.items():
        print(f"\n--- Route: {route} ---")
        for issue in route_issues:
            print(f"\n  Locale: {issue['target_locale']}")
            for line in issue["analysis"].strip().splitlines():
                print(f"    {line}")

    print("\n" + "=" * 60)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python main.py analyze <source_image> <target_image>")
        print("  python main.py crawl <base_url> <source_locale> <target_locale> [target_locale...]")
        print("  python main.py ftl-analyze <screenshots_dir> <source_locale> <target_locale> [target_locale...]")
        sys.exit(1)

    command = sys.argv[1]

    if command == "analyze":
        if len(sys.argv) < 4:
            print("Usage: python main.py analyze <source_image> <target_image>")
            sys.exit(1)
        result = analyze_localization(sys.argv[2], sys.argv[3])
        print(result)

    elif command == "crawl":
        if len(sys.argv) < 5:
            print("Usage: python main.py crawl <base_url> <source_locale> <target_locale> [target_locale...]")
            sys.exit(1)
        crawl_base_url = sys.argv[2]
        crawl_source_locale = sys.argv[3]
        crawl_target_locales = sys.argv[4:]
        found_issues, total_pages = crawl_and_analyze(
            crawl_base_url, crawl_source_locale, crawl_target_locales
        )
        _print_report(found_issues, total_pages)

    elif command == "ftl-analyze":
        if len(sys.argv) < 5:
            print("Usage: python main.py ftl-analyze <screenshots_dir> <source_locale> <target_locale> [target_locale...]")
            sys.exit(1)
        ftl_screenshots_dir = sys.argv[2]
        ftl_source_locale = sys.argv[3]
        ftl_target_locales = sys.argv[4:]
        found_issues = ftl_analyze(
            ftl_screenshots_dir, ftl_source_locale, ftl_target_locales
        )
        _print_ftl_report(found_issues)

    else:
        print(f"Unknown command: {command}")
        print("Available commands: analyze, crawl, ftl-analyze")
        sys.exit(1)
