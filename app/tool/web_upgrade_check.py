#!/usr/bin/env python3
"""Checks that the web app opens data written by an older build.

  web_upgrade_check.py OLD_BUILD NEW_BUILD

Run like web_offline_check.py (same nix shell). Serves OLD_BUILD, creates a
notebook with a stroke in a fresh browser profile; then serves NEW_BUILD at
the same origin with the same profile, lets the service worker update the
app the way it does for users (the first start still runs the cached old
build, which installs the new worker; the next start runs the new build)
and checks that the new build lists and opens the notebook, with nothing
"started fresh", and stores a new stroke next to the old one. Screenshots go to $LEN_CHECK_OUT.
"""
import asyncio, os, re, shutil, sys, tempfile

from playwright.async_api import async_playwright

import web_offline_check as check
from web_offline_check import CheckFailed, PlaywrightTimeout, expect

TITLE = 'From the old build'


def build_version(build):
    with open(os.path.join(build, 'sw.js')) as f:
        return re.search(r'"version":"([^"]+)"', f.read()).group(1)


async def write_with(p, build, profile):
    server = check.serve(build)
    ctx, page = await check.launch(p, profile)
    try:
        await check.open_app(page)
        await check.worker_ready(page)
        await check.draw_in_new_notebook(page, TITLE)
        expect(await check.wait_stored(page, TITLE), 'the old build stored the notebook')
        await check.shot(page, 'upgrade-1-old.png')
    finally:
        await ctx.close()
        check.stop(server)


async def open_with(p, build, profile):
    version = build_version(build)
    server = check.serve(build)
    ctx, page = await check.launch(p, profile)
    try:
        await check.open_app(page)  # Still the cached old build; the new worker installs.
        for _ in range(240):
            if await page.evaluate('caches.keys()') == [f'len-shell-{version}']:
                break
            await page.wait_for_timeout(500)
        else:
            expect(False, 'the new service worker installs')
        await page.reload()
        await page.wait_for_selector('flutter-view', state='attached', timeout=90000)
        expect(await page.evaluate('window.lenTab !== undefined'), 'the new build runs')
        await check.accessible(page)
        listed = await check.wait_text(page, TITLE, timeout=60000)
        await check.shot(page, 'upgrade-2-new.png')
        expect(listed, 'the new build lists the notebook')
        expect(not await check.shows(page, 'started fresh'), 'no "started fresh" notice')
        await page.get_by_role('button', name=re.compile(re.escape(TITLE))).first.click()
        await page.get_by_role('button', name='Back', exact=True).wait_for(timeout=30000)
        await page.wait_for_timeout(1500)
        await check.shot(page, 'upgrade-3-opened.png')
        notebooks = await check.stored(page) or {}
        expect(notebooks.get(TITLE) == 1, f'its stroke is still there: {notebooks}')
        await check.draw(page, dy=80)  # The new build writes into the old store.
        expect(await check.wait_stored(page, TITLE, strokes=2), 'a new stroke is stored next to it')
        await page.reload()
        await check.accessible(page)
        expect(await check.wait_text(page, TITLE, timeout=60000), 'and it all opens again')
        expect((await check.stored(page) or {}).get(TITLE) == 2, 'with both strokes')
    finally:
        await ctx.close()
        check.stop(server)


async def main(old, new):
    os.makedirs(check.OUT, exist_ok=True)
    profile = tempfile.mkdtemp(prefix='len-profile-')
    ok = True
    try:
        async with async_playwright() as p:
            print('old build')
            await write_with(p, old, profile)
            print('new build')
            await open_with(p, new, profile)
    except (CheckFailed, PlaywrightTimeout) as error:
        print('  FAIL', error)
        ok = False
    finally:
        shutil.rmtree(profile, ignore_errors=True)
    print('screenshots:', check.OUT)
    print('passed' if ok else 'failed')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    asyncio.run(main(sys.argv[1], sys.argv[2]))
