import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../data/app_database.dart';

/// A count of write transactions under way on the app's connection, in
/// memory a worker isolate reads too ([WriterWaiting]): the pull worker
/// ends its slice and waits while the app writes, so the app's write waits
/// for one record, not for a whole slice and the lock's polling.
class SharedWriteSignal implements WriteSignal {
  SharedWriteSignal() : _count = calloc<Int32>();

  final Pointer<Int32> _count;
  bool _freed = false;

  /// Where the count is, for [WriterWaiting] in another isolate.
  int get address => _count.address;

  @override
  void begin() {
    if (!_freed) _count.value++;
  }

  @override
  void end() {
    if (!_freed) _count.value--;
  }

  /// Frees the count; only once no isolate reads it anymore.
  void free() {
    if (_freed) return;
    _freed = true;
    calloc.free(_count);
  }
}

/// Reads a [SharedWriteSignal] from another isolate.
class WriterWaiting {
  WriterWaiting(int address) : _count = Pointer<Int32>.fromAddress(address);

  final Pointer<Int32> _count;

  /// Whether the app is writing (or about to).
  bool call() => _count.value > 0;
}
