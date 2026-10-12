/// Making directory entries durable: `fsync` on a directory, which `dart:io`
/// cannot do (it refuses to open directories).
library;

import 'dart:ffi';
import 'dart:io' show FileSystemException, Platform;

import 'package:ffi/ffi.dart';

typedef _OpenC = Int32 Function(Pointer<Utf8> path, Int32 flags);
typedef _OpenDart = int Function(Pointer<Utf8> path, int flags);
typedef _FdC = Int32 Function(Int32 fd);
typedef _FdDart = int Function(int fd);

class _Libc {
  _Libc(DynamicLibrary lib)
    : open = lib.lookupFunction<_OpenC, _OpenDart>('open'),
      fsync = lib.lookupFunction<_FdC, _FdDart>('fsync'),
      close = lib.lookupFunction<_FdC, _FdDart>('close');

  final _OpenDart open;
  final _FdDart fsync;
  final _FdDart close;
}

final _Libc? _libc = (Platform.isLinux || Platform.isMacOS || Platform.isAndroid)
    ? _Libc(DynamicLibrary.process())
    : null;

/// Flushes the directory [path] to disk, so that entries created, renamed
/// or removed in it survive a crash or power loss (POSIX `fsync` on the
/// directory). A no-op on platforms without one (Windows).
///
/// Throws a [FileSystemException] if the directory cannot be opened or
/// synced.
void syncDirectory(String path) {
  final libc = _libc;
  if (libc == null) return;
  final cPath = path.toNativeUtf8();
  try {
    final fd = libc.open(cPath, 0); // O_RDONLY
    if (fd < 0) throw FileSystemException('cannot open directory to sync it', path);
    try {
      if (libc.fsync(fd) != 0) throw FileSystemException('fsync failed', path);
    } finally {
      libc.close(fd);
    }
  } finally {
    malloc.free(cPath);
  }
}
