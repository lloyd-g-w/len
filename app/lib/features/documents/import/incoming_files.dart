import 'dart:async';

import 'package:cross_file/cross_file.dart';

import 'import_targets.dart';

/// Files handed to Len from outside: "Open with" / "Share to Len" on
/// Android, command-line paths on Linux and Windows, the PWA's file
/// handler on the web (see `platform/incoming_files*`), and drops onto the
/// library.
///
/// Batches arriving before anyone handles them (a cold start: the app is
/// launched *with* files, before the library is built) are kept and
/// delivered as soon as a [handler] is set.
class IncomingFiles {
  IncomingFiles([Stream<List<XFile>>? source]) {
    _subscription = source?.listen(add);
  }

  StreamSubscription<List<XFile>>? _subscription;
  final List<List<XFile>> _pending = [];
  void Function(List<XFile> files)? _handler;

  /// Editors that files can be inserted into.
  final ImportTargets targets = ImportTargets();

  /// Who handles batches (the library); null keeps them pending.
  set handler(void Function(List<XFile> files)? handler) {
    _handler = handler;
    if (handler == null) return;
    final pending = [..._pending];
    _pending.clear();
    pending.forEach(handler);
  }

  /// Hands over one batch of files (empty batches are ignored).
  void add(List<XFile> files) {
    if (files.isEmpty) return;
    final handler = _handler;
    if (handler == null) {
      _pending.add(files);
    } else {
      handler(files);
    }
  }

  void dispose() => unawaited(_subscription?.cancel());
}
