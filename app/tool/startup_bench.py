"""Times launches of a Linux bundle built with --dart-define=LEN_STARTUP_TRACE=true.

Run through tool/startup_bench.sh (it provides the virtual display and Mesa).
Each run copies the data template into a fresh XDG_DATA_HOME, starts the
bundle, reads its `len-startup` lines until `interactive` (or a timeout),
and reports every milestone in ms since the process was started.
"""
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

bundle, template, runs = sys.argv[1], sys.argv[2], int(sys.argv[3])
shot = os.environ.get('LEN_BENCH_SHOT')
results = []
turns_all = []
for run in range(runs):
    data = tempfile.mkdtemp(prefix='len-bench-')
    try:
        if template != '-':
            shutil.copytree(template, data, dirs_exist_ok=True)
        env = dict(os.environ, XDG_DATA_HOME=data, XDG_CONFIG_HOME=f'{data}/config',
                   XDG_CACHE_HOME=f'{data}/cache', TMPDIR=data)
        t0 = time.time_ns() // 1000
        proc = subprocess.Popen([bundle], env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        marks, turns, log = {}, [], []
        deadline = time.monotonic() + 60
        for line in proc.stdout:
            log.append(line)
            parts = line.split()
            if line.startswith('len-startup-frame ') and run == 0:
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
        if shot and run == runs - 1:
            subprocess.run(['magick', 'import', '-window', 'root', shot], check=False)
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()
        if 'interactive' not in marks:
            sys.stdout.write(''.join(log[-40:]))
            sys.exit(f'run {run}: no interactive mark')
        results.append(marks)
        turns_all.append(turns)
        print(f'run {run}: ' + ', '.join(f'{k} {v:.0f}' for k, v in marks.items()) +
              f'; long turns {turns}', flush=True)
    finally:
        shutil.rmtree(data, ignore_errors=True)

print('\nmedian ms since launch (min-max):')
for key in results[0]:
    values = [r[key] for r in results if key in r]
    print(f'  {key:12s} {statistics.median(values):7.0f}  ({min(values):.0f}-{max(values):.0f})')
