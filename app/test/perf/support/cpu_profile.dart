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

  Future<void> close() => _service.dispose();
}
