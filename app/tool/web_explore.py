#!/usr/bin/env python3
"""Walks through the web build like a user, in real browsers, and fails on
anything the console, the network or the app reports (see ARCHITECTURE
"Offline"). Widget tests can't see what only breaks once compiled to
JavaScript / WebAssembly and run in a browser; this does.

  tool/build_web.sh                      # or tool/build_web.sh --wasm
  nix shell --impure --expr 'with import (builtins.getFlake "nixpkgs") {};
    buildEnv { name = "len-web-explore"; paths = [ (python3.withPackages
      (p: [ p.playwright ])) chromium xvfb-run playwright-driver.browsers ]; }' \\
    -c env PLAYWRIGHT_BROWSERS_PATH=... python3 tool/web_explore.py build/web

(`tool/web_explore.sh` does exactly that.) Chromium runs headed under Xvfb
(headless Chromium closes the tab at a file chooser and mangles typed
text); Firefox, when Playwright has one, runs headless.

The walk, one fresh profile per browser: first launch → new notebook →
draw with the mouse and with a pen (pointer type pen; its pressure is
stored) → undo / redo → add a page → lasso and move → a text box with bold
→ insert an image (file chooser) → View menu → import a PDF → search it →
export it as PDF (download) → keyboard shortcuts (tools, go to page, focus
mode, Ctrl+/) → settings and the dark theme → back up the library →
offline reload → phone width and sideways phone → open and close a
notebook a few times (memory) → a folder and the list view (cards, folder
tiles and rows are named buttons for screen readers). Then a second fresh
profile restores that backup made big (big_backup: ~20 MB, 4000 strokes, large images, read in
slices on the web) and opens the big notebook at a page with an image and
at its last page.

Collected per step: console errors and warnings, the app's own logs that
say something failed, uncaught exceptions, failed or 4xx/5xx requests,
long tasks (> 200 ms, PerformanceObserver; Chromium) and the JS heap after
a forced GC (Chromium). Any of the first four fails the run, as does a
step whose check fails or a heap that keeps growing while a notebook is
opened and closed again. Long tasks are reported, not failed: startup,
PDF import and restore have some by nature. Except in the big notebook
(open_big) of a WebAssembly build: a task over LONG_TASK_CEILING_MS
there fails the run (it froze the tab). Skwasm renders off the main
thread, so its tasks are the app's own work; CanvasKit (the JavaScript
build) renders on it, and under software GL (Xvfb, CI) one GPU round trip
(a tile's pixels read back, the first frame's shaders) takes 0.3-1.5 s,
so there they are only reported. A failed step also leaves
what a screen reader finds there (<step>.txt).

What was stored is read back from IndexedDB (SQLite) like
web_offline_check.py does. Screenshots of every step go to $LEN_EXPLORE_OUT
(default /tmp/len-web-explore), with report.json. A --wasm build is served
cross-origin isolated (README). Environment:
  LEN_EXPLORE_BROWSERS=chromium,firefox  browsers (default both; Firefox if installed)
  LEN_EXPLORE_BACKUP=<file.len>          only restore this backup (made big) and open it
  LEN_EXPLORE_PROFILE=1                  CPU profile per step, its hottest functions printed
  LEN_EXPLORE_CYCLES=5                   open/close cycles of the memory step
  LEN_EXPLORE_CEILING_MS=500             longest task allowed in the big notebook (WebAssembly)
  LEN_EXPLORE_BUNDLED=1                  Playwright's own Chromium (CI), not the PATH's
Exit status 1 if anything failed.
"""
import asyncio, base64, io, json, os, re, shutil, sqlite3, struct, subprocess, sys, tempfile, time, zipfile, zlib

if not os.environ.get('DISPLAY') and shutil.which('xvfb-run') and not os.environ.get('LEN_EXPLORE_XVFB'):
    # Headed Chromium needs a display: start one.
    os.environ['LEN_EXPLORE_XVFB'] = '1'
    sys.exit(subprocess.call(['xvfb-run', '-a', '-s', '-screen 0 1600x1000x24', sys.executable] + sys.argv))

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import web_offline_check as w  # noqa: E402  (serves BUILD = argv[1]; the shared helpers)
from playwright.async_api import TimeoutError as PlaywrightTimeout, async_playwright  # noqa: E402

OUT = os.environ.get('LEN_EXPLORE_OUT', '/tmp/len-web-explore')

if os.path.exists(os.path.join(w.BUILD, 'main.dart.wasm')):
    class _Isolated(w.Handler):
        """Served as README says for --wasm builds: cross-origin isolated,
        so Skwasm renders with threads."""

        def end_headers(self):
            self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
            self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
            super().end_headers()

    w.Handler = _Isolated
LONG_TASK_MS = 200
LONG_TASK_CEILING_MS = int(os.environ.get('LEN_EXPLORE_CEILING_MS', 500))  # open_big, WebAssembly.
CEILING_STEPS = {'open_big'}
BUNDLED = os.environ.get('LEN_EXPLORE_BUNDLED')  # Playwright's own Chromium, not the PATH's (CI).
PROFILE = os.environ.get('LEN_EXPLORE_PROFILE')  # CPU profile of each step (Chromium).
HEAP_GROWTH_MB = 25  # Allowed JS heap growth over the open/close cycles.

# Console lines that are the browser's or the engine's, not Len's.
BENIGN = [
    r'^Injecting <script> tag', r'GL Driver Message', r'GPU stall due to ReadPixels',
    r'WebGL', r'Webgl', r'Falling back to CPU-only rendering', r'^\[DOM\]',
    r'PDFium', r'PdfrxEntryFunctions', r'Automatic fallback to software WebGL',
]
# Logs (console.log: Flutter's debugPrint) that say something went wrong.
TROUBLE = re.compile(r'fail|error|exception|unsupported|could ?n.t|can.t ', re.I)
# Expected there: a failed write the quota check provokes, never here.
EXPECTED_TROUBLE = [r'^Save picker unavailable']


def png(width, height, noise=False):
    """An opaque PNG (a gradient; [noise]: random, so it doesn't compress),
    no imaging library needed."""
    rows = b''.join(b'\0' + (os.urandom(width * 3) if noise else b''.join(
        bytes((x * 255 // width, y * 255 // height, 160)) for x in range(width)))
        for y in range(height))
    chunk = lambda kind, data: (struct.pack('>I', len(data)) + kind + data
                                + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def pdf(pages):
    """A PDF with one line of text per page (Helvetica, so it's searchable)."""
    n = len(pages)
    objs = ['<< /Type /Catalog /Pages 2 0 R >>',
            f'<< /Type /Pages /Kids [{" ".join(f"{3 + 2 * i} 0 R" for i in range(n))}] /Count {n} >>']
    for i, text in enumerate(pages):
        objs.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
                    f'/Resources << /Font << /F1 {3 + 2 * n} 0 R >> >> /Contents {4 + 2 * i} 0 R >>')
        s = f'BT /F1 28 Tf 72 740 Td ({text}) Tj ET'
        objs.append(f'<< /Length {len(s)} >>\nstream\n{s}\nendstream')
    objs.append('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
    out, offsets = b'%PDF-1.4\n', []
    for i, o in enumerate(objs):
        offsets.append(len(out))
        out += f'{i + 1} 0 obj\n{o}\nendobj\n'.encode()
    xref = len(out)
    out += f'xref\n0 {len(objs) + 1}\n0000000000 65535 f \n'.encode()
    out += b''.join(f'{o:010d} 00000 n \n'.encode() for o in offsets)
    return out + f'trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()


BIG = 'Big backup'
BIG_PAGES, BIG_STROKES, BIG_IMAGES = 40, 100, 4  # Strokes per page; images ~3.6 MB each.


def big_backup(src, dst):
    """[src] (a backup the app wrote) plus notebook BIG: BIG_PAGES pages of
    BIG_STROKES long strokes and BIG_IMAGES incompressible images, in
    records parts of ~4 MB like the app's: some 30 MB, enough for the web
    restore to read in slices (Blob.slice) and to take a while."""
    import hashlib, random, uuid
    rnd = random.Random(7)
    with zipfile.ZipFile(src) as z:
        records = [json.loads(line) for name in sorted(z.namelist()) if name.startswith('records/')
                   for line in z.read(name).decode().splitlines() if line.strip()]
        blobs = json.loads(z.read('blobs.json'))
        files = {n: z.read(n) for n in z.namelist() if n.startswith('blobs/')}
    like = {r['collection']: r for r in records}
    now = int(time.time() * 1000)

    def record(collection, **data):
        r = json.loads(json.dumps(like[collection]))
        r.update(id=str(uuid.uuid4()), updatedAt=now)
        r['data'].update(data)
        return r

    notebook = record('notebooks', title=BIG, createdAt=now, editedAt=now, folderId=None,
                      favorite=False, trashedAt=None)
    pages = [record('pages', notebookId=notebook['id'], sortKey=i + 1, background=None, paper='blank')
             for i in range(BIG_PAGES)]
    strokes, elements = [], []
    for page in pages:
        for k in range(BIG_STROKES):
            x, y, pts = rnd.uniform(60, 700), rnd.uniform(60, 1050), []
            for _ in range(150):
                x, y = x + rnd.uniform(-3, 4), y + rnd.uniform(-3, 3)
                pts.append(struct.pack('<fff', x, y, 0.5))
            strokes.append(record('strokes', surfaceId=page['id'], createdAt=now + k,
                                  points=base64.b64encode(b''.join(pts)).decode()))
    for i in range(BIG_IMAGES):
        data = png(1200, 1000, noise=True)
        sha = hashlib.sha256(data).hexdigest()
        blobs[sha], files[f'blobs/{sha}'] = {'mime': 'image/png', 'size': len(data)}, data
        elements.append(record('elements', type='image', z=-(1 << 20), rotation=0, x=100, y=600,
                               w=480, h=400, surfaceId=pages[i * BIG_PAGES // BIG_IMAGES]['id'],
                               createdAt=now, data={'blob': sha, 'width': 1200, 'height': 1000}))
    order = ['folders', 'templates', 'notebooks', 'pages', 'outline', 'recordings', 'strokes', 'elements']
    added = [notebook] + pages + strokes + elements
    lines = [json.dumps(r, separators=(',', ':')) for r in
             sorted(records + added, key=lambda r: order.index(r['collection']))]
    with zipfile.ZipFile(dst, 'w') as z:
        z.writestr('manifest.json', json.dumps({'format': 'len', 'version': 1, 'kind': 'library',
                                                'title': 'Library', 'createdAt': now}),
                   zipfile.ZIP_DEFLATED)
        part, size, n = [], 0, 0
        for line in lines + [None]:
            if line is None or size + len(line) > 4 << 20:
                n += 1
                z.writestr(f'records/{n:06}.jsonl', '\n'.join(part) + '\n', zipfile.ZIP_DEFLATED)
                part, size = [], 0
            if line is not None:
                part.append(line)
                size += len(line) + 1
        z.writestr('blobs.json', json.dumps(blobs), zipfile.ZIP_DEFLATED)
        for name, data in files.items():
            z.writestr(name, data, zipfile.ZIP_STORED)
    return dst


# --- Watching the page -----------------------------------------------------

# Long tasks into window.lenLongTasks; Len files the save picker would
# write into window.lenSaved (the picker itself is a native dialog).
INIT = '''(() => {
  window.lenLongTasks = [];
  if ((PerformanceObserver.supportedEntryTypes || []).includes('longtask')) try {
    new PerformanceObserver((list) => { for (const e of list.getEntries())
      window.lenLongTasks.push([Math.round(e.startTime), Math.round(e.duration)]); })
      .observe({ type: 'longtask', buffered: true });
  } catch (e) {}
  window.lenSaved = {};
  if (window.showSaveFilePicker) window.showSaveFilePicker = async (options) => {
    const name = (options && options.suggestedName) || 'file', parts = [];
    return { name, createWritable: async () => ({
      write: async (chunk) => { parts.push(chunk instanceof Blob ? chunk : new Blob([chunk])); },
      close: async () => { window.lenSaved[name] = new Blob(parts); },
      abort: async () => {} }) };
  };
})()'''


class Watch:
    """Everything the page reports, by step."""

    def __init__(self, browser):
        self.browser, self.step, self.problems, self.steps = browser, 'start', [], []
        self.downloads = []

    def attach(self, page):
        def console(m):
            text = m.text
            if any(re.search(b, text) for b in BENIGN):
                return
            if m.type in ('error', 'warning') or (m.type in ('log', 'info') and TROUBLE.search(text)
                                                   and not any(re.search(e, text) for e in EXPECTED_TROUBLE)):
                self.problem(f'console {m.type}: {text[:400]}')

        page.on('console', console)
        page.on('pageerror', lambda e: self.problem(f'uncaught: {e}'))
        page.on('crash', lambda *_: self.problem('the tab crashed'))
        page.on('requestfailed', lambda r: None if self.offline else self.problem(
            f'request failed: {r.url} {r.failure}'))
        page.on('response', lambda r: r.status >= 400 and self.problem(f'HTTP {r.status}: {r.url}'))
        page.on('download', lambda d: self.downloads.append(d))

    offline = False

    def problem(self, what):
        print(f'  FAIL [{self.step}] {what}')
        self.problems.append({'browser': self.browser, 'step': self.step, 'problem': what})


def print_hot(profile, top=12):
    """The functions that took the most time themselves in a CPU profile."""
    nodes, own = {n['id']: n for n in profile['nodes']}, {}
    deltas = profile.get('timeDeltas', [])
    for sample, delta in zip(profile.get('samples', []), deltas[1:] + [0]):
        frame = nodes[sample]['callFrame']
        key = f"{frame['functionName'] or '(anonymous)'} {frame['url'].rsplit('/', 1)[-1]}"
        own[key] = own.get(key, 0) + delta / 1000
    for key, ms in sorted(own.items(), key=lambda kv: -kv[1])[:top]:
        print(f'    {ms:8.0f} ms  {key[:150]}')


async def heap_mb(page, cdp):
    """JS heap after a forced GC, in MB (Chromium; None elsewhere)."""
    if cdp is None:
        return None
    await cdp.send('HeapProfiler.collectGarbage')
    metrics = (await cdp.send('Performance.getMetrics'))['metrics']
    return round(next(m['value'] for m in metrics if m['name'] == 'JSHeapUsedSize') / 2 ** 20, 1)


# --- Driving the app (by label, through the semantics tree) ----------------

async def tap(page, label, exact=True, role='button'):
    await page.get_by_role(role, name=label, exact=exact).first.click(timeout=30000)


async def type_text(page, text):
    """Types into the focused field, key by key, and checks it arrived."""
    await page.wait_for_function("document.activeElement && ['INPUT', 'TEXTAREA']"
                                 ".includes(document.activeElement.tagName)", timeout=15000)
    await page.keyboard.type(text, delay=20)
    value = await page.evaluate('document.activeElement.value')
    w.expect(value.endswith(text), f'typed {text!r}: field holds {value!r}')


async def go_to_page(page, number):
    await page.keyboard.press('Control+g')
    await page.wait_for_function('document.activeElement && document.activeElement.tagName === "INPUT"',
                                 timeout=15000)
    await page.keyboard.type(str(number))
    await page.keyboard.press('Enter')


async def expect_text(page, text, timeout=30000):
    w.expect(await w.wait_text(page, text, timeout=timeout), f'shows "{text}"')


async def view_center(page):
    box = await page.locator('flutter-view').bounding_box()
    return box['x'] + box['width'] / 2, box['y'] + box['height'] / 2


async def pen_stroke(page, cdp, x, y):
    """A stroke with pointer type pen and rising pressure (CDP)."""
    send = lambda kind, px, py, **kw: cdp.send('Input.dispatchMouseEvent', {
        'type': kind, 'x': px, 'y': py, 'pointerType': 'pen', **kw})
    await send('mouseMoved', x, y)
    await send('mousePressed', x, y, button='left', clickCount=1, force=0.2)
    for i in range(40):
        await send('mouseMoved', x + i * 6, y + (i % 7) * 3, button='left', buttons=1, force=0.2 + i / 50)
    await send('mouseReleased', x + 240, y, button='left', clickCount=1, force=0)


async def drag(page, points, steps=10):
    await page.mouse.move(*points[0])
    await page.mouse.down()
    for (a, b), (c, d) in zip(points, points[1:]):
        for t in range(1, steps + 1):
            await page.mouse.move(a + (c - a) * t / steps, b + (d - b) * t / steps)
    await page.mouse.up()


async def query(page, sql):
    """Rows of [sql] on the database as stored in IndexedDB."""
    files = await page.evaluate(w._DUMP)
    data = files and files.get('/len.db')
    if not data:
        return []
    with tempfile.NamedTemporaryFile(suffix='.db') as f:
        f.write(base64.b64decode(data))
        f.flush()
        db = sqlite3.connect(f.name)
        try:
            return db.execute(sql).fetchall()
        finally:
            db.close()


async def wait_query(page, sql, ok, what, timeout=20):
    rows = None
    for _ in range(timeout * 2):
        rows = await query(page, sql)
        if ok(rows):
            break
        await page.wait_for_timeout(500)
    w.expect(ok(rows), f'{what}: {rows}')


STROKES = '''SELECT COUNT(*) FROM strokes s JOIN pages p ON p.id = s.surface_id
    JOIN notebooks n ON n.id = p.notebook_id WHERE s.deleted = 0 AND n.title = 'Explore' '''
ELEMENTS = '''SELECT e.type FROM elements e JOIN pages p ON p.id = e.surface_id
    JOIN notebooks n ON n.id = p.notebook_id WHERE e.deleted = 0 AND n.title = 'Explore' '''


async def saved_file(page, watch, name_part, timeout=60):
    """A file the app saved: through the (stubbed) save picker or a download."""
    for _ in range(timeout * 2):
        for d in watch.downloads:
            if name_part in d.suggested_filename:
                watch.downloads.remove(d)
                path = os.path.join(OUT, f'{watch.browser}-{d.suggested_filename}')
                await d.save_as(path)
                return path
        data = await page.evaluate('''async (part) => { for (const [k, b] of Object.entries(window.lenSaved))
            if (k.includes(part)) { delete window.lenSaved[k]; const a = new Uint8Array(await b.arrayBuffer());
              let s = ''; for (let i = 0; i < a.length; i += 0x8000) s += String.fromCharCode(...a.subarray(i, i + 0x8000));
              return [k, btoa(s)]; } return null; }''', name_part)
        if data:
            path = os.path.join(OUT, f'{watch.browser}-{data[0]}')
            with open(path, 'wb') as f:
                f.write(base64.b64decode(data[1]))
            return path
        await page.wait_for_timeout(500)
    w.expect(False, f'a file named like "{name_part}" was saved')


async def pick_file(page, path, action):
    async with page.expect_file_chooser(timeout=30000) as chooser:
        await action()
    await (await chooser.value).set_files(path)


async def wheel(page, dy, times=1):
    x, y = await view_center(page)
    await page.mouse.move(x, y)
    for _ in range(times):
        await page.mouse.wheel(0, dy)
        await page.wait_for_timeout(150)


_NODES = '''() => [...document.querySelectorAll('flt-semantics-host flt-semantics')].map((e) =>
    [e.getAttribute('role') || '', e.getAttribute('aria-label') || '',
     [...e.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join('')]
    .join(' | ')).filter((l) => l.replace(/[ |]/g, ''))'''


async def expect_items(page, names):
    """Each of [names] is a button whose label starts with it and holds no
    other button, before and while the mouse is over it; as many ⋯ as
    items, whether shown or not."""
    async def check(name, hovered):
        item = page.get_by_role('button', name=re.compile('^' + re.escape(name) + r'\b')).first
        await item.wait_for(timeout=15000)
        inner = await item.get_by_role('button').count()
        more = await page.get_by_role('button', name='More', exact=True).count()
        w.expect(inner == 0 and more >= len(names),
                 f'"{name}" is a named button{" (hovered)" if hovered else ""}: '
                 f'{inner} button(s) inside, {more} ⋯')
        return item

    for name in names:
        item = await check(name, False)
        box = await item.bounding_box()
        await page.mouse.move(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
        await page.wait_for_timeout(300)
        await check(name, True)


# --- The walk ----------------------------------------------------------------

class Walk:
    """One browser's walk; each step leaves a screenshot and its findings."""

    def __init__(self, name, page, cdp, watch, fixtures):
        self.name, self.page, self.cdp, self.watch, self.fx = name, page, cdp, watch, fixtures
        self.n, self.tasks_seen, self.wasm = 0, 0, False

    async def step(self, title, body):
        self.n += 1
        self.watch.step = title
        print(f'{self.name} {self.n:02} {title}')
        started = time.monotonic()
        ok = True
        if self.cdp and PROFILE:
            await self.cdp.send('Profiler.enable')
            await self.cdp.send('Profiler.start')
        try:
            await body()
        except (w.CheckFailed, PlaywrightTimeout) as e:
            if isinstance(e, PlaywrightTimeout):
                self.watch.problem(f'timed out: {str(e).splitlines()[0]}')
            else:
                self.watch.problems.append({'browser': self.name, 'step': title, 'problem': str(e)})
            ok = False
        page = self.page
        if not ok:  # What a screen reader would find there, to see why.
            try:
                nodes = await page.evaluate(_NODES)
                with open(os.path.join(OUT, f'{self.name}-{self.n:02}-{title}.txt'), 'w') as f:
                    f.write('\n'.join(nodes))
            except Exception:
                pass
        try:
            await page.screenshot(path=os.path.join(OUT, f'{self.name}-{self.n:02}-{title}.png'))
            tasks = await page.evaluate('window.lenLongTasks || []')
        except Exception as e:  # The page is gone: the findings say why.
            self.watch.problem(f'page unusable: {e}')
            return False
        if self.cdp and PROFILE:
            profile = (await self.cdp.send('Profiler.stop'))['profile']
            with open(os.path.join(OUT, f'{self.name}-{self.n:02}-{title}.cpuprofile'), 'w') as f:
                json.dump(profile, f)
            print_hot(profile)
        new = tasks[self.tasks_seen:]
        long = [t for t in new if t[1] > LONG_TASK_MS]
        self.tasks_seen = len(tasks)
        if title in CEILING_STEPS and new:
            longest = max(t[1] for t in new)
            print(f'  longest task: {longest} ms')
            if self.wasm and longest > LONG_TASK_CEILING_MS:
                self.watch.problem(f'a {longest} ms task froze the tab (ceiling {LONG_TASK_CEILING_MS} ms)')
                ok = False
        heap = await heap_mb(page, self.cdp)
        self.watch.steps.append({'browser': self.name, 'step': title, 'ok': ok,
                                 'seconds': round(time.monotonic() - started, 1),
                                 'long_tasks_ms': [t[1] for t in long], 'heap_mb': heap})
        if long:
            print(f'  long tasks: {", ".join(f"{t[1]} ms" for t in long)}')
        return ok

    # Steps -------------------------------------------------------------------

    async def first_launch(self):
        await w.open_app(self.page)
        await w.worker_ready(self.page)
        await w.accessible(self.page)
        await expect_text(self.page, 'No notebooks yet', timeout=60000)
        await self.note_build()

    async def note_build(self):
        """Which build the page runs: WebAssembly (Skwasm) or JavaScript."""
        self.wasm, isolated = await self.page.evaluate('''() => [performance.getEntriesByType('resource')
            .some((e) => e.name.endsWith('.wasm') && e.name.includes('main.dart')), crossOriginIsolated]''')
        print(f'  running {"WebAssembly" if self.wasm else "JavaScript"}'
              f'{", cross-origin isolated" if isolated else ""}')

    async def new_notebook(self):
        await tap(self.page, 'New notebook')
        await type_text(self.page, 'Explore')
        await self.page.keyboard.press('Enter')
        await self.page.get_by_role('button', name='Back', exact=True).wait_for(timeout=30000)

    async def draw_mouse(self):
        await w.draw(self.page)
        await wait_query(self.page, STROKES, lambda r: r[0][0] == 1, 'one stroke stored')

    async def draw_pen(self):
        x, y = await view_center(self.page)
        if self.cdp:
            # The message shows at pen down for 4 s; on a loaded machine the
            # stroke's events alone can take longer: watch from before it.
            seen = asyncio.ensure_future(w.wait_text(self.page, 'Stylus detected'))
            await pen_stroke(self.page, self.cdp, x - 250, y + 120)
            w.expect(await seen, 'shows "Stylus detected"')
            await wait_query(self.page, STROKES, lambda r: r[0][0] == 2, 'two strokes stored')
            # The pen's pressure arrived: it rises along the stroke.
            (points,), = await query(self.page, STROKES.replace('COUNT(*)', 's.points', 1)
                                     + ' ORDER BY s.created_at DESC LIMIT 1')
            pressures = [p for (_, _, p) in struct.iter_unpack('<fff', points)]
            w.expect(len(pressures) > 10 and pressures[-2] - pressures[1] > 0.3,
                     f'pressure rises: {[round(p, 2) for p in pressures[::8]]}')
        else:  # No pen events without CDP: another mouse stroke.
            await w.draw(self.page, dy=120)
        await wait_query(self.page, STROKES, lambda r: r[0][0] == 2, 'two strokes stored')

    async def undo_redo(self):
        page = self.page
        for action, count in [(lambda: page.keyboard.press('Control+z'), 1),
                              (lambda: page.keyboard.press('Control+Shift+z'), 2),
                              (lambda: tap(page, 'Undo (Ctrl+Z)'), 1),
                              (lambda: tap(page, 'Redo (Ctrl+Shift+Z)'), 2)]:
            await action()
            await wait_query(page, STROKES, lambda r: r[0][0] == count, f'{count} stroke(s) after it')

    async def add_page(self):
        await wheel(self.page, 600, times=10)
        await tap(self.page, 'Add page')
        await expect_text(self.page, 'Page 2 of 2')
        await w.draw(self.page)
        await wait_query(self.page, STROKES, lambda r: r[0][0] == 3, 'a stroke on page 2')

    async def lasso_move(self):
        page = self.page
        box = await page.locator('flutter-view').bounding_box()
        x, y = box['x'] + box['width'] * 0.4, box['y'] + box['height'] * 0.45  # w.draw's stroke
        await page.keyboard.press('l')
        await drag(page, [(x - 40, y - 40), (x + 280, y - 40), (x + 280, y + 70), (x - 40, y + 70),
                          (x - 40, y - 38)])
        # The pill's buttons are named (screen readers).
        await page.get_by_role('button', name='Style').first.wait_for(timeout=15000)
        before = (await query(page, 'SELECT COUNT(*) FROM strokes'))[0][0]
        await drag(page, [(x + 120, y + 12), (x + 180, y + 132)], steps=20)
        await wait_query(page, 'SELECT COUNT(*) FROM strokes', lambda r: r[0][0] > before,
                         'the moved stroke replaced')
        await wait_query(page, STROKES, lambda r: r[0][0] == 3, 'still three strokes')
        await page.keyboard.press('Escape')

    async def text_box(self):
        page = self.page
        x, y = await view_center(page)
        await page.keyboard.press('t')
        await page.mouse.click(x - 200, y - 200)
        await type_text(page, 'Hello web')
        await page.keyboard.press('Control+b')
        await type_text(page, ' bold')
        await page.keyboard.press('Escape')
        await wait_query(page, ELEMENTS.replace('e.type', 'e.data', 1) + " AND e.type = 'text'",
                         lambda r: len(r) == 1 and 'Hello web' in r[0][0] and ' bold' in r[0][0],
                         'the text box stored')

    async def insert_image(self):
        await tap(self.page, 'Insert')
        await pick_file(self.page, self.fx['png'], lambda: tap(self.page, 'Image…'))
        await wait_query(self.page, ELEMENTS + " AND e.type = 'image'", lambda r: len(r) == 1,
                         'the image stored')
        await self.page.keyboard.press('Escape')

    async def view_menu(self):
        await tap(self.page, 'More options')
        await self.page.get_by_role('button', name='View', exact=True).first.hover()
        await expect_text(self.page, 'Focus mode')
        await self.page.wait_for_timeout(300)  # Rendered, glyphs and all, for the screenshot.

    async def import_pdf(self):
        page = self.page
        await page.keyboard.press('Escape')
        await page.keyboard.press('Escape')
        await tap(page, 'Back')
        await tap(page, 'New')
        await pick_file(page, self.fx['pdf'], lambda: tap(page, 'Import PDF…', role='menuitem'))
        await expect_text(page, 'Page 1 of 2', timeout=60000)

    async def search(self):
        x, y = await view_center(self.page)
        await self.page.mouse.move(x, y)
        await self.page.keyboard.press('Control+f')
        await type_text(self.page, 'keeper')
        await expect_text(self.page, 'Lighthouse keeper notes')
        await self.page.keyboard.press('Escape')

    async def export_pdf(self):
        page = self.page
        await page.keyboard.press('Control+e')
        await page.get_by_role('radio', name='All pages').click()
        await tap(page, 'Export')
        path = await saved_file(page, self.watch, '.pdf')
        data = open(path, 'rb').read()
        pages = len(re.findall(rb'/Type\s*/Page[^s]', data))
        w.expect(data.startswith(b'%PDF') and pages == 2, f'a 2-page PDF: {pages} pages, {len(data)} bytes')

    async def shortcuts(self):
        page = self.page
        for key in 'phelp':
            await page.keyboard.press(key)
        await go_to_page(page, 2)
        await expect_text(page, 'Page 2 of 2')
        await page.keyboard.press('F11')
        await page.get_by_role('button', name='Show toolbars (F11)').wait_for(timeout=15000)
        await page.keyboard.press('Control+.')
        await page.get_by_role('button', name='Back', exact=True).wait_for(timeout=15000)
        await page.keyboard.press('Control+/')
        await expect_text(page, 'Ctrl+Shift+Z or Ctrl+Y')
        await page.keyboard.press('Escape')

    async def settings(self):
        page = self.page
        await tap(page, 'Back')
        await tap(page, 'Settings')
        await tap(page, 'Dark')
        await page.keyboard.press('Control+/')
        await expect_text(page, 'Ctrl+Shift+Z or Ctrl+Y')
        await page.keyboard.press('Escape')
        await page.wait_for_timeout(300)

    async def backup(self):
        page = self.page
        await wheel(page, 400, times=6)
        await tap(page, 'Back up library', exact=False)
        path = await saved_file(page, self.watch, '.len')
        try:
            with zipfile.ZipFile(path) as z:
                bad, names = z.testzip(), z.namelist()
        except zipfile.BadZipFile as e:
            bad, names = str(e), []
        w.expect(bad is None and 'manifest.json' in names, f'the backup is a whole zip: {bad} {names[:4]}')
        self.fx['backup'] = path

    async def offline_reload(self):
        page = self.page
        await tap(page, 'Back')
        await expect_text(page, 'Explore')
        self.watch.offline = True
        await page.context.set_offline(True)
        try:
            await page.reload()
            await w.accessible(page)
            await expect_text(page, 'Explore', timeout=60000)
            await expect_text(page, 'fix')
        finally:
            await page.context.set_offline(False)
            self.watch.offline = False

    async def phone(self):
        page = self.page
        await page.set_viewport_size({'width': 390, 'height': 844})
        await page.wait_for_timeout(800)
        await page.screenshot(path=os.path.join(OUT, f'{self.name}-{self.n:02}-phone-library.png'))
        await tap(page, 'Explore', exact=False)
        await page.get_by_role('button', name='Back', exact=True).wait_for(timeout=30000)
        await page.wait_for_timeout(800)
        await page.screenshot(path=os.path.join(OUT, f'{self.name}-{self.n:02}-phone-editor.png'))
        await page.set_viewport_size({'width': 844, 'height': 390})
        await page.wait_for_timeout(800)
        await page.get_by_role('button', name='Back', exact=True).wait_for(timeout=30000)

    async def memory(self):
        """Opens and closes a notebook again and again: the heap settles."""
        page = self.page
        await tap(page, 'Back')
        await page.set_viewport_size({'width': 1200, 'height': 800})
        heaps = []
        for i in range(int(os.environ.get('LEN_EXPLORE_CYCLES', 5))):
            await tap(page, 'Explore', exact=False)
            await page.get_by_role('button', name='Back', exact=True).wait_for(timeout=30000)
            await wheel(page, 300, times=3)
            await tap(page, 'Back')
            await expect_text(page, 'fix')
            heaps.append(await heap_mb(page, self.cdp))
        print(f'  heap after each cycle: {heaps} MB')
        if heaps[0] is not None:
            w.expect(heaps[-1] - heaps[0] < HEAP_GROWTH_MB, f'the heap settles: {heaps} MB')

    async def library_semantics(self):
        """Cards, folder tiles and list rows stay buttons named by their
        title for screen readers, hovered or not, each beside its own ⋯
        (reachable while hidden)."""
        page = self.page
        await tap(page, 'New folder')
        await type_text(page, 'Walk folder')
        await page.keyboard.press('Enter')
        await expect_text(page, 'Walk folder')
        await expect_items(page, ['Walk folder', 'Explore', 'fix'])
        await tap(page, 'View')
        await tap(page, 'List', role='menuitem')
        await page.keyboard.press('Escape')
        await expect_items(page, ['Walk folder', 'Explore', 'fix'])
        await tap(page, 'View')
        await tap(page, 'Grid', role='menuitem')
        await page.keyboard.press('Escape')

    async def restore(self):
        """A fresh profile (a new device) restores the backup, made big."""
        page = self.page
        backup = big_backup(self.fx['backup'], os.path.join(OUT, f'{self.name}-big.len'))
        await w.open_app(page)
        await w.accessible(page)
        await expect_text(page, 'No notebooks yet', timeout=60000)
        await self.note_build()
        await tap(page, 'Settings')
        await wheel(page, 400, times=6)
        started = time.monotonic()
        await pick_file(page, backup, lambda: tap(page, 'Restore from backup', exact=False))
        await expect_text(page, 'Restore this backup?')
        await tap(page, 'Restore')
        await expect_text(page, 'Restored your backup', timeout=300000)
        print(f'  restored {os.path.getsize(backup) >> 20} MB in {time.monotonic() - started:.0f} s')
        await wait_query(page, STROKES, lambda r: r[0][0] == 3, 'the restored notebook\'s strokes')
        await wait_query(page, ELEMENTS, lambda r: sorted(t for (t,) in r) == ['image', 'text'],
                         'its text box and image')
        big = STROKES.replace("'Explore'", f"'{BIG}'")
        await wait_query(page, big, lambda r: r[0][0] == BIG_PAGES * BIG_STROKES, f'{BIG}\'s strokes')
        await wait_query(page, ELEMENTS.replace("'Explore'", f"'{BIG}'"),
                         lambda r: [t for (t,) in r] == ['image'] * BIG_IMAGES, f'{BIG}\'s images')

    async def open_big(self):
        """The restored big notebook opens, its last page too."""
        page = self.page
        await page.keyboard.press('Escape')
        await tap(page, 'Back')
        await tap(page, BIG, exact=False)
        await page.get_by_role('button', name='Back', exact=True).wait_for(timeout=60000)
        last_image = (BIG_IMAGES - 1) * BIG_PAGES // BIG_IMAGES + 1  # A page with an image.
        for number in (last_image, BIG_PAGES):
            await go_to_page(page, number)
            await expect_text(page, f'Page {number} of {BIG_PAGES}')
            await wheel(page, 200, times=2)  # The image in view.
            await page.wait_for_timeout(4000)  # Painted, for the screenshot.
            await page.screenshot(path=os.path.join(OUT, f'{self.name}-big-page-{number}.png'))
        await tap(page, 'Back')
        await expect_text(page, 'Explore')

    def main_steps(self):
        return [self.first_launch, self.new_notebook, self.draw_mouse, self.draw_pen, self.undo_redo,
                self.add_page, self.lasso_move, self.text_box, self.insert_image, self.view_menu,
                self.import_pdf, self.search, self.export_pdf, self.shortcuts, self.settings,
                self.backup, self.offline_reload, self.phone, self.memory, self.library_semantics]


async def launch(p, browser, profile):
    common = dict(viewport={'width': 1200, 'height': 800}, accept_downloads=True)
    if browser == 'chromium':
        ctx = await p.chromium.launch_persistent_context(
            profile, executable_path=None if BUNDLED else shutil.which('chromium'), headless=False,
            args=['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'], **common)
    else:
        ctx = await p.firefox.launch_persistent_context(profile, headless=True, **common)
    await ctx.add_init_script(INIT)
    page = ctx.pages[0] if ctx.pages else await ctx.new_page()
    cdp = None
    if browser == 'chromium':
        cdp = await ctx.new_cdp_session(page)
        await cdp.send('Performance.enable')
    return ctx, page, cdp


async def explore(p, browser, fixtures):
    watch = Watch(browser)
    profile = tempfile.mkdtemp(prefix='len-explore-')
    server = w.serve()
    try:
        ctx, page, cdp = await launch(p, browser, profile)
        watch.attach(page)
        walk = Walk(browser, page, cdp, watch, fixtures)
        if os.environ.get('LEN_EXPLORE_BACKUP'):  # Only the restore, of this backup.
            fixtures['backup'] = os.environ['LEN_EXPLORE_BACKUP']
        try:
            for step in [] if os.environ.get('LEN_EXPLORE_BACKUP') else walk.main_steps():
                if not await walk.step(step.__name__, step):
                    break
        finally:
            await ctx.close()
        if 'backup' in fixtures:
            shutil.rmtree(profile, ignore_errors=True)
            ctx, page, cdp = await launch(p, browser, profile)
            watch.attach(page)
            walk.page, walk.cdp, walk.tasks_seen = page, cdp, 0
            try:
                if await walk.step('restore', walk.restore):
                    await walk.step('open_big', walk.open_big)
            finally:
                await ctx.close()
    finally:
        w.stop(server)
        shutil.rmtree(profile, ignore_errors=True)
    return watch


def firefox_installed(p):
    try:
        return os.path.exists(p.firefox.executable_path)
    except Exception:
        return False


async def main():
    os.makedirs(OUT, exist_ok=True)
    fixtures = {'png': os.path.join(OUT, 'fixture.png'), 'pdf': os.path.join(OUT, 'fix.pdf')}
    with open(fixtures['png'], 'wb') as f:
        f.write(png(320, 200))
    with open(fixtures['pdf'], 'wb') as f:
        f.write(pdf(['Lighthouse keeper notes', 'Second page of the fixture']))
    wanted = [b for b in os.environ.get('LEN_EXPLORE_BROWSERS', 'chromium,firefox').split(',') if b]
    watches = []
    async with async_playwright() as p:
        for browser in wanted:
            if browser == 'firefox' and not firefox_installed(p):
                print('firefox: not installed, skipped')
                continue
            watches.append(await explore(p, browser, dict(fixtures)))
    problems = [x for watch in watches for x in watch.problems]
    steps = [x for watch in watches for x in watch.steps]
    with open(os.path.join(OUT, 'report.json'), 'w') as f:
        json.dump({'problems': problems, 'steps': steps}, f, indent=1)
    print('screenshots and report.json:', OUT)
    print(f'{len(problems)} problem(s)' if problems else 'no problems')
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    asyncio.run(main())
