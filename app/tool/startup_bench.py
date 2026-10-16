"""Times launches of Linux bundles built with --dart-define=LEN_STARTUP_TRACE=true.

Run through tool/startup_bench.sh (it provides the virtual display and Mesa).
Each run copies the data template into a fresh XDG_DATA_HOME, starts a
bundle, reads its `len-startup` lines until `interactive` (or a timeout),
and reports every milestone in ms since the process was started. Several
bundles (before / after) take turns, so a busy machine skews them alike.
"""
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time

template, runs, bundles = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
shot = os.environ.get('LEN_BENCH_SHOT')
results = {b: [] for b in bundles}


def launch(bundle, run):
    data = tempfile.mkdtemp(prefix='len-bench-')
    try:
        if template != '-':
            shutil.copytree(template, data, dirs_exist_ok=True)
        # Mesa's shader cache stays warm, as on a desktop that ran Len before
        # (it would live in XDG_CACHE_HOME); Len's own cache is fresh.
        env = dict(os.environ, XDG_DATA_HOME=data, XDG_CONFIG_HOME=f'{data}/config',
                   XDG_CACHE_HOME=f'{data}/cache', TMPDIR=data,
                   MESA_SHADER_CACHE_DIR=os.path.join(tempfile.gettempdir(), 'len-bench-mesa'))
        t0 = time.time_ns() // 1000
        proc = subprocess.Popen([bundle], env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        marks, turns, log = {}, [], []
        deadline = time.monotonic() + 60
        watchdog = threading.Timer(90, proc.kill)
        watchdog.start()
        for line in proc.stdout:
            log.append(line)
            parts = line.split()
            if line.startswith('len-startup-frame ') and os.environ.get('LEN_BENCH_FRAMES'):
                print('  ' + line.strip())
            if line.startswith('len-startup-turn '):
                turns.append((int(parts[1]), int(parts[3].strip('+ms'))))
            elif line.startswith('len-startup '):
                marks[parts[1] if len(parts) == 4 else ' '.join(parts[1:-2])] = \
                    (int(parts[-2]) - t0) / 1000
                if parts[1] == 'interactive':
                    break
            if time.monotonic() > deadline:
                break
        if shot and run == runs - 1 and bundle == bundles[-1]:
            subprocess.run(['magick', 'import', '-window', 'root', shot], check=False)
        watchdog.cancel()
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()
        if 'interactive' not in marks:
            sys.stdout.write(''.join(log[-40:]))
            sys.exit(f'{bundle} run {run}: no interactive mark')
        results[bundle].append(marks)
        print(f'{bundle} run {run}: ' + ', '.join(f'{k} {v:.0f}' for k, v in marks.items()) +
              f'; long turns {turns}', flush=True)
    finally:
        shutil.rmtree(data, ignore_errors=True)


for run in range(runs):
    for bundle in bundles:
        launch(bundle, run)

for bundle in bundles:
    print(f'\n{bundle}: median ms since launch (min-max) of {runs}:')
    for key in results[bundle][0]:
        values = [r[key] for r in results[bundle] if key in r]
        print(f'  {key:12s} {statistics.median(values):7.0f}  ({min(values):.0f}-{max(values):.0f})')
