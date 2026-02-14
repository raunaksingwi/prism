import subprocess
import sys
import tempfile
from unittest.mock import MagicMock, patch

import pytest
from PIL import Image

from main import (
    _build_locale_url,
    _extract_same_domain_links,
    _print_report,
    _safe_filename,
    _strip_locale_prefix,
    analyze_localization,
    crawl_and_analyze,
)


# ---------------------------------------------------------------------------
# _strip_locale_prefix
# ---------------------------------------------------------------------------


class TestStripLocalePrefix:
    def test_strips_prefix_from_subpath(self):
        assert _strip_locale_prefix("/en/about", "en") == "/about"

    def test_strips_prefix_exact_match_returns_root(self):
        assert _strip_locale_prefix("/en", "en") == "/"

    def test_strips_prefix_deep_path(self):
        assert _strip_locale_prefix("/fr/docs/api/v2", "fr") == "/docs/api/v2"

    def test_no_prefix_returns_unchanged(self):
        assert _strip_locale_prefix("/about", "en") == "/about"

    def test_root_path_returns_unchanged(self):
        assert _strip_locale_prefix("/", "en") == "/"

    def test_different_locale_not_stripped(self):
        assert _strip_locale_prefix("/fr/about", "en") == "/fr/about"

    def test_partial_locale_match_not_stripped(self):
        # "/english/about" should NOT be stripped by locale "en"
        assert _strip_locale_prefix("/english/about", "en") == "/english/about"


# ---------------------------------------------------------------------------
# _build_locale_url
# ---------------------------------------------------------------------------


class TestBuildLocaleUrl:
    def test_basic(self):
        assert (
            _build_locale_url("https://example.com", "fr", "/about")
            == "https://example.com/fr/about"
        )

    def test_root_route(self):
        assert (
            _build_locale_url("https://example.com", "en", "/")
            == "https://example.com/en/"
        )

    def test_strips_trailing_slash_from_base(self):
        assert (
            _build_locale_url("https://example.com/", "es", "/contact")
            == "https://example.com/es/contact"
        )

    def test_deep_route(self):
        assert (
            _build_locale_url("https://example.com", "de", "/docs/api/v2")
            == "https://example.com/de/docs/api/v2"
        )


# ---------------------------------------------------------------------------
# _safe_filename
# ---------------------------------------------------------------------------


class TestSafeFilename:
    def test_root(self):
        assert _safe_filename("/") == "index"

    def test_single_segment(self):
        assert _safe_filename("/about") == "about"

    def test_multi_segment(self):
        assert _safe_filename("/about/team") == "about_team"

    def test_deep_path(self):
        assert _safe_filename("/docs/api/v2/auth") == "docs_api_v2_auth"

    def test_empty_string(self):
        assert _safe_filename("") == "index"


# ---------------------------------------------------------------------------
# _extract_same_domain_links
# ---------------------------------------------------------------------------


class TestExtractSameDomainLinks:
    def test_filters_external_links(self):
        mock_page = MagicMock()
        mock_page.eval_on_selector_all.return_value = [
            "https://example.com/en/about",
            "https://other.com/page",
            "https://example.com/en/contact",
        ]
        result = _extract_same_domain_links(mock_page, "https://example.com")
        assert result == {"/en/about", "/en/contact"}

    def test_strips_trailing_slash(self):
        mock_page = MagicMock()
        mock_page.eval_on_selector_all.return_value = [
            "https://example.com/en/about/",
        ]
        result = _extract_same_domain_links(mock_page, "https://example.com")
        assert result == {"/en/about"}

    def test_preserves_root(self):
        mock_page = MagicMock()
        mock_page.eval_on_selector_all.return_value = [
            "https://example.com/",
        ]
        result = _extract_same_domain_links(mock_page, "https://example.com")
        assert result == {"/"}

    def test_empty_page(self):
        mock_page = MagicMock()
        mock_page.eval_on_selector_all.return_value = []
        result = _extract_same_domain_links(mock_page, "https://example.com")
        assert result == set()


# ---------------------------------------------------------------------------
# crawl_and_analyze (integration with mocks)
# ---------------------------------------------------------------------------


class TestCrawlAndAnalyze:
    @patch("main.sync_playwright")
    @patch("main.analyze_localization")
    def test_crawls_homepage_and_discovered_links(
        self, mock_analyze, mock_pw_ctx
    ):
        """BFS discovers /about from homepage, visits both routes."""
        mock_analyze.return_value = "No localization issues detected."

        # Set up Playwright mocks
        mock_page = MagicMock()
        mock_browser = MagicMock()
        mock_browser.new_page.return_value = mock_page
        mock_pw = MagicMock()
        mock_pw.chromium.launch.return_value = mock_browser
        mock_pw_ctx.return_value.__enter__ = MagicMock(return_value=mock_pw)
        mock_pw_ctx.return_value.__exit__ = MagicMock(return_value=False)

        # Homepage links include /en/about; /about page has no new links
        call_count = 0

        def fake_links(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 1:  # homepage source
                return ["https://example.com/en/about"]
            return []  # all other pages

        mock_page.eval_on_selector_all.side_effect = fake_links

        issues, pages_crawled = crawl_and_analyze(
            "https://example.com", "en", ["fr"], max_pages=10
        )

        assert pages_crawled == 2  # / and /about
        assert issues == []
        # analyze_localization called once per route per target locale
        assert mock_analyze.call_count == 2

    @patch("main.sync_playwright")
    @patch("main.analyze_localization")
    def test_collects_issues_when_drift_detected(
        self, mock_analyze, mock_pw_ctx
    ):
        mock_analyze.return_value = "- Header: text truncated → increase max-width"

        mock_page = MagicMock()
        mock_browser = MagicMock()
        mock_browser.new_page.return_value = mock_page
        mock_pw = MagicMock()
        mock_pw.chromium.launch.return_value = mock_browser
        mock_pw_ctx.return_value.__enter__ = MagicMock(return_value=mock_pw)
        mock_pw_ctx.return_value.__exit__ = MagicMock(return_value=False)

        mock_page.eval_on_selector_all.return_value = []

        issues, pages_crawled = crawl_and_analyze(
            "https://example.com", "en", ["fr"], max_pages=5
        )

        assert pages_crawled == 1
        assert len(issues) == 1
        assert issues[0]["route"] == "/"
        assert issues[0]["target_locale"] == "fr"
        assert "truncated" in issues[0]["analysis"]

    @patch("main.sync_playwright")
    @patch("main.analyze_localization")
    def test_respects_max_pages(self, mock_analyze, mock_pw_ctx):
        mock_analyze.return_value = "No localization issues detected."

        mock_page = MagicMock()
        mock_browser = MagicMock()
        mock_browser.new_page.return_value = mock_page
        mock_pw = MagicMock()
        mock_pw.chromium.launch.return_value = mock_browser
        mock_pw_ctx.return_value.__enter__ = MagicMock(return_value=mock_pw)
        mock_pw_ctx.return_value.__exit__ = MagicMock(return_value=False)

        # Every page returns 3 new links — without max_pages this would explode
        counter = {"val": 0}

        def infinite_links(*args, **kwargs):
            counter["val"] += 1
            n = counter["val"]
            return [f"https://example.com/en/page{n}_{i}" for i in range(3)]

        mock_page.eval_on_selector_all.side_effect = infinite_links

        issues, pages_crawled = crawl_and_analyze(
            "https://example.com", "en", ["fr"], max_pages=3
        )

        assert pages_crawled == 3

    @patch("main.sync_playwright")
    @patch("main.analyze_localization")
    def test_skips_page_on_navigation_error(self, mock_analyze, mock_pw_ctx):
        mock_page = MagicMock()
        mock_browser = MagicMock()
        mock_browser.new_page.return_value = mock_page
        mock_pw = MagicMock()
        mock_pw.chromium.launch.return_value = mock_browser
        mock_pw_ctx.return_value.__enter__ = MagicMock(return_value=mock_pw)
        mock_pw_ctx.return_value.__exit__ = MagicMock(return_value=False)

        # Source page.goto raises an error
        mock_page.goto.side_effect = Exception("net::ERR_CONNECTION_REFUSED")
        mock_page.eval_on_selector_all.return_value = []

        issues, pages_crawled = crawl_and_analyze(
            "https://example.com", "en", ["fr"], max_pages=5
        )

        assert pages_crawled == 1
        assert issues == []
        # analyze_localization should never be called since source failed
        mock_analyze.assert_not_called()

    @patch("main.sync_playwright")
    @patch("main.analyze_localization")
    def test_multiple_target_locales(self, mock_analyze, mock_pw_ctx):
        mock_analyze.return_value = "No localization issues detected."

        mock_page = MagicMock()
        mock_browser = MagicMock()
        mock_browser.new_page.return_value = mock_page
        mock_pw = MagicMock()
        mock_pw.chromium.launch.return_value = mock_browser
        mock_pw_ctx.return_value.__enter__ = MagicMock(return_value=mock_pw)
        mock_pw_ctx.return_value.__exit__ = MagicMock(return_value=False)

        mock_page.eval_on_selector_all.return_value = []

        issues, pages_crawled = crawl_and_analyze(
            "https://example.com", "en", ["fr", "es", "de"], max_pages=1
        )

        assert pages_crawled == 1
        # One analysis per target locale
        assert mock_analyze.call_count == 3


# ---------------------------------------------------------------------------
# _print_report
# ---------------------------------------------------------------------------


class TestPrintReport:
    def test_no_issues(self, capsys):
        _print_report([], 5)
        output = capsys.readouterr().out
        assert "Pages crawled: 5" in output
        assert "Issues found: 0" in output
        assert "No localization issues detected" in output

    def test_with_issues(self, capsys):
        issues = [
            {
                "route": "/",
                "target_locale": "fr",
                "analysis": "- Header: text truncated",
            },
            {
                "route": "/about",
                "target_locale": "es",
                "analysis": "- Button: text overflow",
            },
        ]
        _print_report(issues, 10)
        output = capsys.readouterr().out
        assert "Pages crawled: 10" in output
        assert "Issues found: 2" in output
        assert "Route: /" in output
        assert "Route: /about" in output
        assert "fr" in output
        assert "es" in output

    def test_groups_by_route(self, capsys):
        issues = [
            {"route": "/", "target_locale": "fr", "analysis": "issue 1"},
            {"route": "/", "target_locale": "es", "analysis": "issue 2"},
        ]
        _print_report(issues, 1)
        output = capsys.readouterr().out
        # Route "/" should appear exactly once as a header
        assert output.count("Route: /") == 1


# ---------------------------------------------------------------------------
# analyze_localization
# ---------------------------------------------------------------------------


class TestAnalyzeLocalization:
    def test_missing_api_key_raises(self, monkeypatch):
        monkeypatch.delenv("GEMINI_API_KEY", raising=False)
        with pytest.raises(RuntimeError, match="GEMINI_API_KEY"):
            analyze_localization("a.png", "b.png")

    @patch("main.genai.Client")
    @patch("main.Image.open")
    def test_returns_model_response(self, mock_open, mock_client_cls, monkeypatch):
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        mock_open.return_value = MagicMock()

        mock_response = MagicMock()
        mock_response.text = "No localization issues detected."
        mock_client = MagicMock()
        mock_client.models.generate_content.return_value = mock_response
        mock_client_cls.return_value = mock_client

        result = analyze_localization("source.png", "target.png")

        assert result == "No localization issues detected."
        mock_client.models.generate_content.assert_called_once()

    @patch("main.genai.Client")
    @patch("main.Image.open")
    def test_custom_prompt_passed_to_model(self, mock_open, mock_client_cls, monkeypatch):
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        mock_open.return_value = MagicMock()

        mock_response = MagicMock()
        mock_response.text = "custom result"
        mock_client = MagicMock()
        mock_client.models.generate_content.return_value = mock_response
        mock_client_cls.return_value = mock_client

        result = analyze_localization("s.png", "t.png", prompt="custom prompt")

        call_args = mock_client.models.generate_content.call_args
        contents = call_args.kwargs.get("contents") or call_args[1].get("contents")
        assert contents[-1] == "custom prompt"


# ---------------------------------------------------------------------------
# _extract_same_domain_links (additional edge cases)
# ---------------------------------------------------------------------------


class TestExtractSameDomainLinksEdgeCases:
    def test_relative_path_without_leading_slash(self):
        mock_page = MagicMock()
        mock_page.eval_on_selector_all.return_value = [
            "about",  # relative, no netloc
        ]
        result = _extract_same_domain_links(mock_page, "https://example.com")
        assert result == {"/about"}


# ---------------------------------------------------------------------------
# crawl_and_analyze — target locale navigation error
# ---------------------------------------------------------------------------


class TestCrawlAndAnalyzeTargetError:
    @patch("main.sync_playwright")
    @patch("main.analyze_localization")
    def test_skips_target_on_navigation_error(self, mock_analyze, mock_pw_ctx):
        """If a target locale page fails to load, it's skipped but source still works."""
        mock_page = MagicMock()
        mock_browser = MagicMock()
        mock_browser.new_page.return_value = mock_page
        mock_pw = MagicMock()
        mock_pw.chromium.launch.return_value = mock_browser
        mock_pw_ctx.return_value.__enter__ = MagicMock(return_value=mock_pw)
        mock_pw_ctx.return_value.__exit__ = MagicMock(return_value=False)

        mock_page.eval_on_selector_all.return_value = []

        # First goto (source) succeeds, second (target) fails
        call_num = {"n": 0}

        def goto_side_effect(url, **kwargs):
            call_num["n"] += 1
            if call_num["n"] == 2:  # target locale goto
                raise Exception("Timeout")

        mock_page.goto.side_effect = goto_side_effect

        issues, pages_crawled = crawl_and_analyze(
            "https://example.com", "en", ["fr"], max_pages=1
        )

        assert pages_crawled == 1
        assert issues == []
        mock_analyze.assert_not_called()


# ---------------------------------------------------------------------------
# CLI __main__ block
# ---------------------------------------------------------------------------


class TestCLI:
    def test_no_args_shows_usage(self):
        result = subprocess.run(
            [sys.executable, "main.py"],
            capture_output=True, text=True,
            cwd="/Users/raunak/Code/gemini-hackathon/diamond",
        )
        assert result.returncode == 1
        assert "Usage:" in result.stdout

    def test_unknown_command(self):
        result = subprocess.run(
            [sys.executable, "main.py", "bogus"],
            capture_output=True, text=True,
            cwd="/Users/raunak/Code/gemini-hackathon/diamond",
        )
        assert result.returncode == 1
        assert "Unknown command: bogus" in result.stdout

    def test_analyze_missing_args(self):
        result = subprocess.run(
            [sys.executable, "main.py", "analyze"],
            capture_output=True, text=True,
            cwd="/Users/raunak/Code/gemini-hackathon/diamond",
        )
        assert result.returncode == 1
        assert "analyze <source_image>" in result.stdout

    def test_crawl_missing_args(self):
        result = subprocess.run(
            [sys.executable, "main.py", "crawl", "https://example.com"],
            capture_output=True, text=True,
            cwd="/Users/raunak/Code/gemini-hackathon/diamond",
        )
        assert result.returncode == 1
        assert "crawl <base_url>" in result.stdout
