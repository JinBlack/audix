#!/usr/bin/env python3
"""Playwright smoke test for the Audix Flutter web build.

Loads the app, waits for boot + drift's wasm DB, enables Flutter's
accessibility tree, navigates every bottom-nav tab and asserts the app stays
error-free and the Settings screen renders real content.

Usage:
  python3 tool/web/smoke_test.py <url> <chromium-executable> [out-dir] [video-dir]

When [video-dir] is given, a screen recording is written to
<video-dir>/audix-web-smoke.webm. Exit code 0 on success, 1 on failure.
"""
import os
import sys
from playwright.sync_api import sync_playwright

URL = sys.argv[1]
EXE = sys.argv[2]
OUT = sys.argv[3] if len(sys.argv) > 3 else "/tmp/audix-web"
VIDEO_DIR = sys.argv[4] if len(sys.argv) > 4 else None

errors = []
ok = True
os.makedirs(OUT, exist_ok=True)

# Playwright records video at the CSS *viewport* size, and Flutter's web layout
# is driven by that logical width — so a phone-sized viewport gives a tight,
# phone-like layout. device_scale_factor only adds rendering sharpness (it does
# not change the layout), so render at 2x. Default: 414x896 (phone portrait).
VIEW_W = int(os.environ.get("AUDIX_VIEW_W", "414"))
VIEW_H = int(os.environ.get("AUDIX_VIEW_H", "896"))
SCALE = float(os.environ.get("AUDIX_SCALE", "2"))

with sync_playwright() as p:
    browser = p.chromium.launch(
        executable_path=EXE,
        headless=True,
        args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
    )
    ctx_args = {
        "viewport": {"width": VIEW_W, "height": VIEW_H},
        "device_scale_factor": SCALE,
    }
    if VIDEO_DIR:
        os.makedirs(VIDEO_DIR, exist_ok=True)
        ctx_args["record_video_dir"] = VIDEO_DIR
        # Match the viewport so the app fills the whole frame.
        ctx_args["record_video_size"] = {"width": VIEW_W, "height": VIEW_H}
    context = browser.new_context(**ctx_args)
    page = context.new_page()
    page.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(9000)

    # Enable Flutter's semantics tree (JS click bypasses the off-screen guard).
    page.evaluate("() => document.querySelector('flt-semantics-placeholder')?.click()")
    page.wait_for_timeout(2500)

    def labels():
        return page.eval_on_selector_all(
            "flt-semantics[aria-label]",
            "els => els.map(e => e.getAttribute('aria-label')).filter(Boolean)",
        )

    nav = labels()
    print("nav labels:", nav)
    for tab in ("Library", "Bookmarks", "Servers", "Settings"):
        if tab not in nav:
            print(f"FAIL: nav destination '{tab}' not found")
            ok = False

    for tab in ("Bookmarks", "Servers", "Settings", "Library"):
        el = page.query_selector(f'flt-semantics[aria-label="{tab}"]')
        if not el:
            continue
        el.click(force=True)
        page.wait_for_timeout(2500)
        page.screenshot(path=f"{OUT}/tab_{tab.lower()}.png")
        if tab == "Settings" and "Skip interval" not in labels():
            print("FAIL: Settings content did not render")
            ok = False

    video = page.video
    context.close()  # flushes the recording
    if VIDEO_DIR and video:
        dest = os.path.join(VIDEO_DIR, "audix-web-smoke.webm")
        try:
            video.save_as(dest)
            print("VIDEO:", dest)
        except Exception as e:
            print("video save failed:", e)
    browser.close()

if errors:
    print("PAGE ERRORS:", errors)
    ok = False

print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
