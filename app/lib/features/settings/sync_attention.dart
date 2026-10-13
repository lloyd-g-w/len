import 'dart:async';

import 'package:flutter/material.dart';

import '../../sync/sync_controller.dart';
import '../../ui/messages.dart';
import 'settings_screen.dart';

/// Says once, wherever the user is, when sync stops because the server
/// refused the access token (retrying can't fix that, so sync waits for
/// the settings): a snack bar with Settings. Said again only after sync has
/// worked (or been turned off) in between.
class SyncAttention {
  SyncAttention({required this.sync, required this.messenger, required this.navigator}) {
    sync.addListener(_changed);
  }

  final SyncController sync;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final GlobalKey<NavigatorState> navigator;
  bool _told = false;

  void _changed() {
    if (!sync.waitsForSettings) {
      if (sync.state == SyncState.idle || sync.state == SyncState.disabled) _told = false;
      return;
    }
    final context = messenger.currentContext;
    if (_told || context == null) return;
    _told = true;
    final state = messenger.currentState;
    if (state == null) return;
    MessageQueue.show(
      state,
      appSnackBar(
        context,
        'Sync stopped: the server refused the access token',
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => unawaited(
            navigator.currentState?.push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen(showSync: true)),
            ),
          ),
        ),
      ),
    );
  }

  void dispose() => sync.removeListener(_changed);
}
