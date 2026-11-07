"""Render icon.svg: icon-400.png for CurseForge, ../Media/icon.tga for the addon list, and 64/32 px previews."""
import io, pathlib
from PIL import Image
from playwright.sync_api import sync_playwright

here = pathlib.Path(__file__).resolve().parent
svg = (here / "icon.svg").read_text(encoding="utf-8")


def render(browser, size):
    page = browser.new_page(viewport={"width": size, "height": size})
    sized = svg.replace('width="512" height="512"', f'width="{size}" height="{size}"')
    page.set_content(f'<html><body style="margin:0;background:transparent">{sized}</body></html>')
    return Image.open(io.BytesIO(page.screenshot(omit_background=True))).convert("RGBA")


with sync_playwright() as p:
    browser = p.chromium.launch()
    big = render(browser, 1024)
    browser.close()

# The small sizes come from the big render so every edge is supersampled.
big.resize((400, 400), Image.LANCZOS).save(here / "icon-400.png")
icon64 = big.resize((64, 64), Image.LANCZOS)
icon64.save(here / "icon-64.png")
icon64.save(here.parent / "Media" / "icon.tga")
big.resize((32, 32), Image.LANCZOS).save(here / "icon-32.png")
