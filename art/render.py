"""Render icon.svg: icon-400.png for CurseForge, ../Media/icon.tga for the addon list and the minimap button."""
import io, pathlib
from PIL import Image
from playwright.sync_api import sync_playwright

here = pathlib.Path(__file__).resolve().parent
svg = (here / "icon.svg").read_text()


def render(browser, size):
    page = browser.new_page(viewport={"width": size, "height": size})
    sized = svg.replace('width="512" height="512"', f'width="{size}" height="{size}"')
    page.set_content(f'<html><body style="margin:0;background:transparent">{sized}</body></html>')
    return Image.open(io.BytesIO(page.screenshot(omit_background=True)))


with sync_playwright() as p:
    browser = p.chromium.launch()
    render(browser, 400).save(here / "icon-400.png")
    render(browser, 64).convert("RGBA").save(here.parent / "Media" / "icon.tga")
    browser.close()
