import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/write_back.dart';
import '../../ui/messages.dart';

/// Says once, wherever the user is, when changes can't be saved (a full
/// browser storage): a snack bar with Try again. The changes stay in
/// memory and are retried; when they are saved, a short message says so.
/// Said again only after saving has worked in between. The library shows
/// a notice for as long as it lasts.
class StorageAttention {
  StorageAttention({required this.writes, required this.messenger}) {
    writes.addListener(_changed);
  }

  final StorageWrites writes;
  final GlobalKey<ScaffoldMessengerState> messenger;
  bool _told = false;

  /// The title of the lasting notices (library, Settings → Storage).
  static const unsavedTitle = 'Your latest changes aren’t saved yet';

  /// The explanation under [unsavedTitle].
  static String unsavedBody(WriteFailure failure) => switch (failure) {
    WriteFailure.full =>
      'Browser storage is full. Len keeps the changes in this tab and saves them '
          'once there’s room: free up space, and keep this tab open until then.',
    WriteFailure.failed =>
      'Len keeps the changes in this tab and keeps trying to save them. Keep this '
          'tab open until then.',
  };

  /// What to say while [failure] lasts.
  static String messageFor(WriteFailure failure) => switch (failure) {
    WriteFailure.full =>
      'Browser storage is full: your latest changes are kept in this tab until there’s room',
    WriteFailure.failed => 'Your latest changes couldn’t be saved yet: Len keeps trying',
  };

  void _changed() {
    final failure = writes.failure;
    final context = messenger.currentContext;
    if (failure == null) {
      if (_told && !writes.pending && context != null) {
        _told = false;
        final state = messenger.currentState?..hideCurrentSnackBar();
        if (state != null) MessageQueue.show(state, appSnackBar(context, 'Your changes are saved'));
      }
      return;
    }
    if (_told || context == null) return;
    _told = true;
    final state = messenger.currentState;
    if (state == null) return;
    MessageQueue.show(
      state,
      appSnackBar(
        context,
        messageFor(failure),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(label: 'Try again', onPressed: () => unawaited(writes.flush())),
      ),
    );
  }

  void dispose() => writes.removeListener(_changed);
}
