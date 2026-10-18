// vm_service comes with flutter_test; a dev dependency would only pin it.
// ignore_for_file: depend_on_referenced_packages
import 'dart:developer' as developer;
import 'dart:isolate' as iso;

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Where a benchmark spends its time, from the VM's CPU samples: run the
/// test with `flutter test --enable-vmservice`, then
/// `final p = (await tester.runAsync(CpuProfile.connect))!;`,
/// `await tester.runAsync(p.start);` … `await tester.runAsync(() => p.dump('label'));`
/// (see docs/PERFORMANCE.md).
class CpuProfile {
  CpuProfile._(this._service, this._isolate);
  final VmService _service;
  final String _isolate;
  int _start = 0;

  static Future<CpuProfile?> connect() async {
    var info = await developer.Service.getInfo();
    if (info.serverUri == null) {
      info = await developer.Service.controlWebServer(enable: true, silenceOutput: true);
    }
    final uri = info.serverWebSocketUri;
    if (uri == null) return null;
    final service = await vmServiceConnectUri(uri.toString());
    final id = developer.Service.getIsolateId(iso.Isolate.current)!;
    return CpuProfile._(service, id);
  }

  /// Starts sampling, every [period] µs if given (the VM's default: 1,000).
  Future<void> start({int? period}) async {
    if (period != null) await _service.setFlag('profile_period', '$period');
    await _service.clearCpuSamples(_isolate);
    _start = (await _service.getVMTimelineMicros()).timestamp!;
  }

  /// Prints the top [count] functions by inclusive and exclusive samples.
  Future<void> dump(String label, {int count = 40, String filter = ''}) async {
    final now = (await _service.getVMTimelineMicros()).timestamp!;
    final samples = await _service.getCpuSamples(_isolate, _start, now - _start);
    final fns = samples.functions!;
    final exclusive = <int, int>{};
    final inclusive = <int, int>{};
    for (final s in samples.samples!) {
      final stack = s.stack!;
      if (stack.isEmpty) continue;
      exclusive.update(stack.first, (v) => v + 1, ifAbsent: () => 1);
      for (final f in stack.toSet()) {
        inclusive.update(f, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    String name(int i) {
      final f = fns[i].function;
      String fn(FuncRef f) {
        final owner = f.owner;
        if (owner is ClassRef) return '${owner.name}.${f.name}';
        if (owner is FuncRef) return '${fn(owner)}.${f.name}';
        if (owner is LibraryRef) return '${owner.uri?.split('/').last}:${f.name}';
        return f.name ?? '?';
      }

      if (f is FuncRef) return fn(f);
      if (f is NativeFunction) return 'native ${f.name}';
      return '$f';
    }

    // ignore: avoid_print
    print('=== $label: ${samples.sampleCount} samples');
    final inc = inclusive.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var shown = 0;
    for (final e in inc) {
      final n = name(e.key);
      if (filter.isNotEmpty && !RegExp(filter).hasMatch(n)) continue;
      // ignore: avoid_print
      print('  incl ${e.value}  excl ${exclusive[e.key] ?? 0}  $n');
      if (++shown >= count) break;
    }
  }

  /// Records the VM's timeline ([streams]: garbage collection, the
  /// compiler, Dart's own events such as the frame's phases, and the
  /// engine's, such as `DoMakeRasterSnapshot` for `Picture.toImage`) from
  /// now on; [dumpTimeline] prints it. The test harness runs the engine's
  /// raster tasks on the UI thread: CPU samples without Dart frames are
  /// mostly those.
  Future<void> startTimeline({
    List<String> streams = const ['GC', 'Compiler', 'Dart', 'Embedder'],
  }) async {
    await _service.setVMTimelineFlags(streams);
    await _service.clearVMTimeline();
    _timelineStart = (await _service.getVMTimelineMicros()).timestamp!;
  }

  int _timelineStart = 0;

  /// Prints the timeline events since [startTimeline] that took at least
  /// [minMs], in order (start relative to it, duration, stream, name).
  Future<void> dumpTimeline(String label, {double minMs = 1}) async {
    final now = (await _service.getVMTimelineMicros()).timestamp!;
    final timeline = await _service.getVMTimeline(
      timeOriginMicros: _timelineStart,
      timeExtentMicros: now - _timelineStart,
    );
    // Complete events, and begin/end pairs (per thread; async ones by id).
    final raw = [
      for (final e in timeline.traceEvents ?? const <TimelineEvent>[])
        if (e.json case final j? when j['ts'] != null) j,
    ]..sort((a, b) => (a['ts'] as num).compareTo(b['ts'] as num));
    final open = <String, List<Map<String, dynamic>>>{};
    final events = <Map<String, dynamic>>[];
    for (final j in raw) {
      final ph = j['ph'];
      final key = ph == 'b' || ph == 'e' ? 'a${j['id']}' : 't${j['tid']}';
      if (ph == 'X') {
        events.add(j);
      } else if (ph == 'B' || ph == 'b') {
        (open[key] ??= []).add(j);
      } else if ((ph == 'E' || ph == 'e') && (open[key]?.isNotEmpty ?? false)) {
        final b = open[key]!.removeLast();
        events.add({...b, 'dur': (j['ts'] as num) - (b['ts'] as num)});
      }
    }
    events
      ..retainWhere((j) => (j['dur'] as num? ?? 0) >= minMs * 1000)
      ..sort((a, b) => (a['ts'] as num).compareTo(b['ts'] as num));
    // ignore: avoid_print
    print('=== timeline $label: ${events.length} events ≥ $minMs ms');
    for (final e in events) {
      final at = ((e['ts'] as num) - _timelineStart) / 1000;
      final ms = (e['dur'] as num) / 1000;
      // ignore: avoid_print
      print(
        '  +${at.toStringAsFixed(1)} ms  ${ms.toStringAsFixed(1)} ms  ${e['cat']} ${e['name']}',
      );
    }
  }

  Future<void> close() => _service.dispose();
}
