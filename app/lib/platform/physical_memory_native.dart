import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// `MemTotal` of /proc/meminfo on Android and Linux, Windows'
/// `GetPhysicallyInstalledSystemMemory`; null elsewhere or on failure.
final int? physicalMemoryBytes = _read();

int? _read() {
  try {
    if (Platform.isLinux || Platform.isAndroid) {
      final line = File('/proc/meminfo')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('MemTotal:'), orElse: () => '');
      final kb = int.tryParse(RegExp(r'(\d+)').firstMatch(line)?.group(1) ?? '');
      return kb == null ? null : kb * 1024;
    }
    if (Platform.isWindows) {
      final get = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<Int32 Function(Pointer<Uint64>), int Function(Pointer<Uint64>)>(
            'GetPhysicallyInstalledSystemMemory',
          );
      final kb = calloc<Uint64>();
      try {
        return get(kb) != 0 ? kb.value * 1024 : null;
      } finally {
        calloc.free(kb);
      }
    }
  } on Object {
    return null;
  }
  return null;
}
