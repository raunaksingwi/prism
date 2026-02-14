import os
import sys

from dotenv import load_dotenv
from google import genai
from PIL import Image

load_dotenv()

DEFAULT_PROMPT = """You are a localization QA expert comparing two screenshots of the same screen in an Android app:

1. **Source screenshot** (first image) — the original language version
2. **Target screenshot** (second image) — the translated/localized version

**IMPORTANT CONTEXT — These screenshots come from automated UI crawling:**
The screenshots may be captured mid-interaction. The following are NORMAL and must NOT be flagged:
- Keyboard being open/visible (the bot is typing in fields)
- Form fields being focused or highlighted
- Dropdown menus or pickers being open
- Screens captured mid-scroll or mid-transition
- Loading states, spinners, or partial content loading
- Modal dialogs or bottom sheets being open
- Content scrolled to show lower portions of a screen
- Keyboard pushing content up (expected Android behavior)

**What to flag — REAL localization issues (compare target against source):**
1. **Text truncation**: Translated text cut off without ellipsis where the source text fits fine
2. **Text overflow**: Translated strings spilling outside their container or overlapping adjacent elements
3. **Broken layout**: Elements misaligned, wrong size, or visually broken in target but fine in source
4. **Untranslated strings**: Text still in the source language that should have been translated
5. **Clipped elements**: Icons, buttons, or images clipped due to text expansion from translation
6. **Inconsistent spacing/alignment**: Padding or alignment noticeably different from source, suggesting hardcoded dimensions
7. **RTL layout issues**: Mirroring problems if the target language is RTL (if applicable)
8. **Missing content**: Content visible in source but absent in target (not loading states)

**Only report high-confidence issues.** If something looks like it *might* be an issue but could also be a normal interaction state, do not report it.

For each issue, output a concise, actionable fix instruction that a coding agent can use. Format as plain text, one issue per line:

- [Element/area]: [Issue description] → [Suggested fix]

If no issues are found, respond with: "No localization issues detected."
"""


def analyze_localization(
    source_image_path: str,
    target_image_path: str,
    prompt: str | None = None,
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


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python main.py <source_image> <target_image> [prompt]")
        sys.exit(1)

    source = sys.argv[1]
    target = sys.argv[2]
    custom_prompt = sys.argv[3] if len(sys.argv) > 3 else None

    result = analyze_localization(source, target, custom_prompt)
    print(result)
