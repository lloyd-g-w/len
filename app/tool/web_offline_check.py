#!/usr/bin/env python3
"""Checks the web build in headless Chromium (see ARCHITECTURE "Offline").

  tool/build_web.sh
  nix shell --impure --expr 'with import (builtins.getFlake "nixpkgs") {};
    buildEnv { name = "len-web-check";
      paths = [ (python3.withPackages (p: [ p.playwright ])) chromium ]; }' \\
    -c python3 tool/web_offline_check.py build/web

Scenarios (each in a fresh browser profile; LEN_CHECK_ONLY=offline,quota
runs a subset):

* offline: serves the build, waits for the service worker, creates a
  notebook ("Offline test") and draws a stroke; then, with the server
  stopped and the browser offline, the app starts from the worker's cache
  and lists the notebook, also after a reload.
* quota: with the origin's quota exhausted a new notebook stays in the tab,
  the library and Settings → Storage say it isn't saved; once there is room
  again, Try again saves it and it survives a reload. The quota comes from
  CDP Storage.overrideQuotaForOrigin; where that has no effect (Chromium
  153 headless ignores it), IndexedDB write transactions abort with a
  QuotaExceededError instead, as a full origin's do.
* tabs: a second tab waits; reloading the first tab keeps Len there; an edit
  made just before the second tab's "Use here" reaches it.

The app is driven by label through Flutter's semantics tree (enabled like a
screen reader would) and by keyboard, never by screen positions. Text is
entered before the semantics tree is enabled (Flutter web's semantic text
fields don't take input from automation) as one insertion (typed keys
reach Flutter with a stale caret, so only the last one stays). What was
stored is read back from IndexedDB with Python's sqlite3.

Screenshots go to $LEN_CHECK_OUT (default /tmp/len-offline-check);
LEN_CHECK_PORT picks the port (default: a free one). Exit status 1 if any
check fails.
"""
import asyncio, base64, functools, http.server, json, os, shutil, socket, sqlite3, sys, tempfile, threading

from playwright.async_api import TimeoutError as PlaywrightTimeout, async_playwright

BUILD = sys.argv[1] if len(sys.argv) > 1 else 'build/web'
OUT = os.environ.get('LEN_CHECK_OUT', '/tmp/len-offline-check')


def _free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


PORT = int(os.environ.get('LEN_CHECK_PORT') or _free_port())
ORIGIN = f'http://localhost:{PORT}'
URL = ORIGIN + '/'


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.js': 'text/javascript', '.mjs': 'text/javascript'}

    def send_head(self):
        # Always the whole file: builds served one after the other at the same
        # URL (web_upgrade_check.py) can have older modification times.
        del self.headers['If-Modified-Since']
        return super().send_head()

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def log_message(self, *args):
        pass


def serve(build=None):
    server = http.server.ThreadingHTTPServer(
        ('127.0.0.1', PORT), functools.partial(Handler, directory=build or BUILD))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def stop(server):
    server.shutdown()
    server.server_close()


async def launch(p, profile):
    ctx = await p.chromium.launch_persistent_context(
        profile, executable_path=shutil.which('chromium'), headless=True,
        args=['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
        viewport={'width': 1200, 'height': 800})
    return ctx, (ctx.pages[0] if ctx.pages else await ctx.new_page())


class CheckFailed(Exception):
    pass


def expect(ok, what):
    print(('  ok   ' if ok else '  FAIL ') + what)
    if not ok:
        raise CheckFailed(what)


async def shot(page, name):
    await page.screenshot(path=os.path.join(OUT, name))


async def open_app(page):
    await page.goto(URL)
    await page.wait_for_selector('flutter-view', state='attached', timeout=90000)


async def worker_ready(page):
    await page.wait_for_function('navigator.serviceWorker.controller !== null', timeout=60000)


# --- Keyboard (before the semantics tree is on) ---------------------------

async def new_notebook(page, title):
    """Library → Ctrl+N → title → Enter: opens the new notebook. Waits for
    the app to start (the dialog focuses its title field)."""
    focused = "document.activeElement && document.activeElement.tagName === 'INPUT'"
    for _ in range(20):
        await page.keyboard.press('Control+n')
        try:
            await page.wait_for_function(focused, timeout=5000)
            break
        except PlaywrightTimeout:
            pass
    else:
        expect(False, 'the New notebook dialog opens (Ctrl+N)')
    await page.keyboard.insert_text(title)
    value = await page.evaluate('document.activeElement.value')
    expect(value == title, f'title entered: {value!r}')
    await page.keyboard.press('Enter')


# --- Semantics tree --------------------------------------------------------

async def accessible(page):
    """Turns on Flutter's semantics tree (the hidden "Enable accessibility"
    button a screen reader would press). Needed again after each load."""
    await page.wait_for_selector('flt-semantics-placeholder', state='attached', timeout=90000)
    await page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
    await page.wait_for_selector('flt-semantics-host flt-semantics', state='attached', timeout=30000)


_HAS_TEXT = '''(text) => [...document.querySelectorAll('flt-semantics-host *')].some((e) =>
    (e.getAttribute('aria-label') || '').includes(text) ||
    [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.includes(text)))'''


async def shows(page, text):
    return await page.evaluate(_HAS_TEXT, text)


async def wait_text(page, text, timeout=30000, gone=False):
    script = f'(text) => {"!" if gone else ""}({_HAS_TEXT})(text)'
    try:
        await page.wait_for_function(script, arg=text, timeout=timeout)
        return True
    except PlaywrightTimeout:
        return False


async def tap(page, label, timeout=30000):
    await page.get_by_role('button', name=label, exact=True).first.click(timeout=timeout)


async def scroll_to(page, text, steps=20):
    """Scrolls (the mouse wheel over the middle of the app) until [text] is
    in the semantics tree, which leaves out what is scrolled far away."""
    box = await page.locator('flutter-view').bounding_box()
    await page.mouse.move(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
    for _ in range(steps):
        if await shows(page, text):
            return
        await page.mouse.wheel(0, 400)
        await page.wait_for_timeout(200)


async def draw(page, dy=0):
    """A stroke across the middle of the app."""
    box = await page.locator('flutter-view').bounding_box()
    x, y = box['x'] + box['width'] * 0.4, box['y'] + box['height'] * 0.45 + dy
    await page.mouse.move(x, y)
    await page.mouse.down()
    for i in range(30):
        await page.mouse.move(x + i * 8, y + (i % 5) * 6)
    await page.mouse.up()


async def draw_in_new_notebook(page, title, back=True):
    """Creates notebook [title], draws a stroke; back in the library after."""
    await new_notebook(page, title)
    await accessible(page)
    await page.get_by_role('button', name='Back', exact=True).wait_for(timeout=30000)
    await draw(page)
    await page.wait_for_timeout(500)
    if back:
        await tap(page, 'Back')
        expect(await wait_text(page, title), f'the library lists "{title}"')


# --- What IndexedDB holds -------------------------------------------------

_DUMP = '''async () => {
  if (!(await indexedDB.databases()).some((d) => d.name === 'len')) return null;
  const req = (r) => new Promise((ok, fail) => { r.onsuccess = () => ok(r.result); r.onerror = () => fail(r.error); });
  const db = await req(indexedDB.open('len'));
  if (!db.objectStoreNames.contains('files')) { db.close(); return null; }
  const tx = db.transaction(['files', 'blocks'], 'readonly');
  const files = tx.objectStore('files'), blocks = tx.objectStore('blocks');
  const [fk, fv, bk, bv] = await Promise.all([req(files.getAllKeys()), req(files.getAll()),
    req(blocks.getAllKeys()), req(blocks.getAll())]);
  db.close();
  const out = {};
  for (let i = 0; i < fk.length; i++) {
    const bytes = new Uint8Array(fv[i].length);
    for (let j = 0; j < bk.length; j++) {
      if (bk[j][0] !== fk[i] || bk[j][1] >= bytes.length) continue;
      const v = bv[j] instanceof Blob ? await bv[j].arrayBuffer() : bv[j];
      const b = new Uint8Array(v).subarray(0, bytes.length - bk[j][1]);
      bytes.set(b, bk[j][1]);
    }
    let s = '';
    for (let k = 0; k < bytes.length; k += 0x8000) s += String.fromCharCode(...bytes.subarray(k, k + 0x8000));
    out[fv[i].name] = btoa(s);
  }
  return out;
}'''


async def stored(page):
    """{title: live strokes} of the notebooks stored in IndexedDB (None if
    there is no database yet)."""
    files = await page.evaluate(_DUMP)
    data = files and files.get('/len.db')
    if not data:
        return None
    with tempfile.NamedTemporaryFile(suffix='.db') as f:
        f.write(base64.b64decode(data))
        f.flush()
        db = sqlite3.connect(f.name)
        try:
            rows = db.execute('''SELECT n.title, COUNT(s.id) FROM notebooks n
                LEFT JOIN pages p ON p.notebook_id = n.id AND p.deleted = 0
                LEFT JOIN strokes s ON s.surface_id = p.id AND s.deleted = 0
                WHERE n.deleted = 0 GROUP BY n.id''').fetchall()
        except sqlite3.DatabaseError:
            return None
        finally:
            db.close()
    return dict(rows)


async def wait_stored(page, title, timeout=20, strokes=1):
    for _ in range(timeout * 2):
        notebooks = await stored(page) or {}
        if notebooks.get(title, -1) >= strokes:
            return True
        await page.wait_for_timeout(500)
    return False


# --- A full storage --------------------------------------------------------

# While `window.lenCheckFull` is set, IndexedDB write transactions fail the
# way they do on a full origin: aborted, `error` a QuotaExceededError.
_FULL_SHIM = '''(() => {
  const transaction = IDBDatabase.prototype.transaction;
  IDBDatabase.prototype.transaction = function (stores, mode, ...rest) {
    const tx = transaction.call(this, stores, mode, ...rest);
    if (mode === 'readwrite' && window.lenCheckFull) {
      const error = new DOMException('Quota exceeded (simulated)', 'QuotaExceededError');
      Object.defineProperty(tx, 'error', { get: () => error });
      queueMicrotask(() => { try { tx.abort(); } catch (e) {} });
    }
    return tx;
  };
})()'''

_PROBE_WRITE = '''async () => {
  const req = (r) => new Promise((ok, fail) => { r.onsuccess = () => ok(r.result); r.onerror = () => fail(r.error); });
  const open = indexedDB.open('len-check-probe');
  open.onupgradeneeded = () => open.result.createObjectStore('s');
  const db = await req(open);
  const tx = db.transaction('s', 'readwrite');
  tx.objectStore('s').put(new ArrayBuffer(1 << 20), 1);
  const result = await new Promise((ok) => { tx.oncomplete = () => ok('stored');
    tx.onabort = () => ok(tx.error ? tx.error.name : 'aborted'); });
  db.close();
  await req(indexedDB.deleteDatabase('len-check-probe'));
  return result;
}'''


async def fill_storage(page, cdp, full):
    """Exhausts (or restores) the origin's quota; returns how."""
    if full:
        await cdp.send('Storage.overrideQuotaForOrigin', {'origin': ORIGIN, 'quotaSize': 1})
        if await page.evaluate(_PROBE_WRITE) == 'QuotaExceededError':
            return 'quota override'
    else:
        await cdp.send('Storage.overrideQuotaForOrigin', {'origin': ORIGIN})
    await page.evaluate(f'window.lenCheckFull = {"true" if full else "false"}')
    return 'simulated'


# --- Scenarios ------------------------------------------------------------

async def offline(p, profile):
    server = serve()
    ctx, page = await launch(p, profile)
    try:
        await open_app(page)
        await worker_ready(page)
        await draw_in_new_notebook(page, 'Offline test')
        expect(await wait_stored(page, 'Offline test'), 'the notebook and its stroke are stored')
        loads = await page.evaluate('''performance.getEntriesByType('resource')
            .filter((e) => e.name.endsWith('/sqlite3.wasm')).length''')
        expect(loads == 1, f'SQLite loaded once: {loads}')
        await shot(page, 'offline-1-online.png')
        await page.wait_for_timeout(11000)  # The page reports early files to the worker at 10 s.
        caches = await page.evaluate('''async () => { const o = {};
            for (const k of await caches.keys()) o[k] = (await (await caches.open(k)).keys()).length;
            return o; }''')
        print('  caches:', json.dumps(caches))
    finally:
        await ctx.close()
        stop(server)

    ctx, page = await launch(p, profile)
    try:
        await ctx.set_offline(True)
        await open_app(page)
        await accessible(page)
        listed = await wait_text(page, 'Offline test', timeout=60000)
        await shot(page, 'offline-2-start.png')
        expect(await page.evaluate('navigator.serviceWorker.controller !== null'),
               'offline start served by the worker')
        expect(listed, 'offline start lists the notebook')
        await page.reload()
        await accessible(page)
        expect(await wait_text(page, 'Offline test', timeout=60000), 'offline reload lists it')
    finally:
        await ctx.close()


async def quota(p, profile):
    server = serve()
    ctx, page = await launch(p, profile)
    cdp = await ctx.new_cdp_session(page)
    await ctx.add_init_script(_FULL_SHIM)
    title = 'Kept while full'
    try:
        await open_app(page)
        await worker_ready(page)
        for _ in range(60):  # The app has created its database.
            if await stored(page) is not None:
                break
            await page.wait_for_timeout(500)
        print('  storage full:', await fill_storage(page, cdp, True))
        await draw_in_new_notebook(page, title)
        expect(await wait_text(page, "aren't saved yet"), 'the library says changes aren\'t saved')
        await shot(page, 'quota-1-full.png')
        expect(title not in (await stored(page) or {}), 'nothing reached the full storage')
        await tap(page, 'Settings')
        await scroll_to(page, 'Space used')
        said = await wait_text(page, "aren't saved yet")
        await shot(page, 'quota-2-settings.png')
        expect(said, 'Settings → Storage says so too')
        await page.go_back()
        expect(await wait_text(page, title), 'back in the library')

        await fill_storage(page, cdp, False)
        await tap(page, 'Try again')
        expect(await wait_text(page, "aren't saved yet", gone=True), 'the notice goes once saved')
        expect(await wait_stored(page, title), 'the kept notebook and stroke are stored')
        await page.reload()
        await accessible(page)
        expect(await wait_text(page, title, timeout=60000), 'they survive a reload')
        await shot(page, 'quota-3-saved.png')
    finally:
        await ctx.close()
        stop(server)


async def tabs(p, profile):
    server = serve()
    ctx, first = await launch(p, profile)
    waiting = 'Len is open in another tab'
    try:
        await open_app(first)
        await draw_in_new_notebook(first, 'Handed over')
        second = await ctx.new_page()
        await open_app(second)
        await accessible(second)
        expect(await wait_text(second, waiting), 'a second tab waits')

        # Reloading the tab that has Len open keeps it there.
        await first.reload()
        await first.wait_for_selector('flutter-view', state='attached', timeout=90000)
        await draw_in_new_notebook(first, 'Last edit', back=False)  # Ctrl+N works: it's back.
        await second.wait_for_timeout(1500)
        expect(await shows(second, waiting) and not await shows(second, 'Handed over'),
               'after reloading the first tab, the second still waits')
        await shot(second, 'tabs-1-waiting.png')

        # "Use here" right after an edit: the edit comes along.
        await draw(first, dy=60)
        await tap(second, 'Use here')
        expect(await wait_text(second, 'Last edit', timeout=60000), 'Use here opens Len there')
        expect(await wait_text(second, 'Handed over'), 'with the earlier notebook')
        notebooks = await stored(second) or {}
        expect(notebooks.get('Last edit') == 2, f'both strokes arrived: {notebooks}')
        await shot(second, 'tabs-2-used-here.png')
        await accessible(first)
        expect(await wait_text(first, waiting, timeout=60000), 'the first tab now waits')
    finally:
        await ctx.close()
        stop(server)


SCENARIOS = {'offline': offline, 'quota': quota, 'tabs': tabs}


async def main():
    os.makedirs(OUT, exist_ok=True)
    only = [s for s in os.environ.get('LEN_CHECK_ONLY', '').split(',') if s]
    failed = []
    async with async_playwright() as p:
        for name, scenario in SCENARIOS.items():
            if only and name not in only:
                continue
            print(name)
            profile = tempfile.mkdtemp(prefix='len-profile-')
            try:
                await scenario(p, profile)
            except (CheckFailed, PlaywrightTimeout) as error:
                if isinstance(error, PlaywrightTimeout):
                    print('  FAIL', error)
                failed.append(name)
            finally:
                shutil.rmtree(profile, ignore_errors=True)
    print('screenshots:', OUT)
    print('failed:' if failed else 'all passed', ', '.join(failed))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    asyncio.run(main())
