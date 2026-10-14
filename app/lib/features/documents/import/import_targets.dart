import 'dart:async';

import 'package:cross_file/cross_file.dart';

import '../../../domain/cancellation.dart';
import 'import_router.dart';

/// An open editor that incoming files can be inserted into. The editor
/// registers itself with [ImportTargets] while it is shown.
abstract interface class ImportTarget {
  /// The notebook being edited.
  String get notebookId;

  /// What the router needs to know about it.
  ImportDestination get destination;

  /// Inserts the pages of PDF [file] after the current page; a Cancel
  /// there cancels [batch] (the files dropped with it).
  Future<void> insertPdf(XFile file, {CancellationToken? batch});

  /// Inserts [files] as images on the current page or the canvas.
  Future<void> insertImages(List<XFile> files);
}

/// The editors currently shown (normally at most one; two while tabs
/// switch). The most recently registered one is [active].
class ImportTargets {
  final List<ImportTarget> _targets = [];
  final Map<String, List<Completer<ImportTarget>>> _waiting = {};

  /// The shown editor, if any.
  ImportTarget? get active => _targets.lastOrNull;

  /// Called by an editor once it is shown.
  void add(ImportTarget target) {
    _targets
      ..remove(target)
      ..add(target);
    for (final waiter in _waiting.remove(target.notebookId) ?? const <Completer<ImportTarget>>[]) {
      waiter.complete(target);
    }
  }

  /// Called by an editor when it goes.
  void remove(ImportTarget target) => _targets.remove(target);

  /// The editor of [notebookId] once it is shown; null if it isn't within
  /// [timeout].
  Future<ImportTarget?> waitFor(
    String notebookId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final shown = _targets.where((t) => t.notebookId == notebookId).lastOrNull;
    if (shown != null) return shown;
    final waiter = Completer<ImportTarget>();
    _waiting.putIfAbsent(notebookId, () => []).add(waiter);
    try {
      return await waiter.future.timeout(timeout);
    } on TimeoutException {
      _waiting[notebookId]?.remove(waiter);
      return null;
    }
  }
}
