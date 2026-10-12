#!/usr/bin/env python3
"""Checks the offline PWA in headless Chromium (see README "Develop").

  tool/build_web.sh
  nix-shell -p "python3.withPackages(p:[p.playwright])" chromium \\
    --run "python3 tool/web_offline_check.py build/web"

1. Serves the build on localhost, opens it in a fresh profile, waits for the
   service worker, creates a notebook ("Offline test") and draws a stroke.
2. Stops the server, sets the browser offline, starts it again with the same
   profile: the app must load from the worker's cache and list the notebook.
Screenshots go to $LEN_CHECK_OUT (default /tmp/len-offline-check). Click positions assume the
1200×800 window used here.
"""
import asyncio, functools, http.server, json, os, shutil, sys, tempfile, threading

from playwright.async_api import async_playwright

BUILD = sys.argv[1] if len(sys.argv) > 1 else 'build/web'
OUT = os.environ.get('LEN_CHECK_OUT', '/tmp/len-offline-check')
PORT = 8123
URL = f'http://localhost:{PORT}/'


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.js': 'text/javascript', '.mjs': 'text/javascript'}

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def log_message(self, *args):
        pass


def serve():
    server = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), functools.partial(Handler, directory=BUILD))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


async def launch(p, profile):
    ctx = await p.chromium.launch_persistent_context(
        profile, executable_path=shutil.which('chromium'), headless=True,
        args=['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
        viewport={'width': 1200, 'height': 800})
    return ctx, (ctx.pages[0] if ctx.pages else await ctx.new_page())


async def started(page, name):
    await page.wait_for_selector('flutter-view', state='attached', timeout=60000)
    await page.wait_for_timeout(4000)
    await page.screenshot(path=os.path.join(OUT, name))


async def main():
    os.makedirs(OUT, exist_ok=True)
    profile = tempfile.mkdtemp(prefix='len-profile-')
    server = serve()
    async with async_playwright() as p:
        ctx, page = await launch(p, profile)
        await page.goto(URL)
        await started(page, '1-online.png')
        await page.wait_for_function('navigator.serviceWorker.controller !== null', timeout=60000)
        await page.mouse.click(735, 565)  # "New notebook"
        await page.wait_for_timeout(2500)
        await page.keyboard.type('Offline test')
        await page.mouse.click(1000, 706)  # "Create"
        await page.wait_for_timeout(2500)
        await page.mouse.move(500, 400)
        await page.mouse.down()
        for i in range(30):
            await page.mouse.move(500 + i * 8, 400 + (i % 5) * 6)
        await page.mouse.up()
        await page.wait_for_timeout(12000)  # IndexedDB write-back, late resource caching
        caches = await page.evaluate('''async () => { const o = {};
            for (const k of await caches.keys()) o[k] = (await (await caches.open(k)).keys()).length;
            return o; }''')
        print('caches:', json.dumps(caches))
        await ctx.close()
        server.shutdown()

        ctx, page = await launch(p, profile)
        await ctx.set_offline(True)
        await page.goto(URL)
        await started(page, '2-offline.png')
        controlled = await page.evaluate('navigator.serviceWorker.controller !== null')
        await ctx.close()
    shutil.rmtree(profile, ignore_errors=True)
    print('offline start served by the worker:', controlled)
    print('screenshots:', OUT, '(2-offline.png should list "Offline test")')
    sys.exit(0 if controlled else 1)


asyncio.run(main())
