import 'dart:async';

import 'package:flutter/material.dart';

import '../../sync/sync_controller.dart';
import '../../ui/messages.dart';
import 'settings_screen.dart';
import 'sync_alert_button.dart';

/// Says once, wherever the user is, when sync stops because the server
/// refused the access token (retrying can't fix that, so sync waits for
/// the settings), and when it has failed for a day ([longFailure], UX_AUDIT
/// R7-14: a server unreachable for days goes unnoticed otherwise): a snack
/// bar with Settings. Said again only after sync has worked (or been
/// turned off) in between.
class SyncAttention {
  SyncAttention({required this.sync, required this.messenger, required this.navigator}) {
    sync.addListener(_changed);
  }

  final SyncController sync;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final GlobalKey<NavigatorState> navigator;
  bool _told = false;
  bool _toldLong = false;

  /// How long sync fails, since it last worked, before it is said.
  static const Duration longFailure = Duration(days: 1);

  /// Whether sync fails now and hasn't worked for [longFailure].
  bool get _failingLong {
    if (sync.state != SyncState.error) return false;
    final since = sync.lastSuccess ?? sync.failingSince;
    return since != null && sync.clock.nowDate().difference(since) >= longFailure;
  }

  void _changed() {
    if (sync.state == SyncState.idle || sync.state == SyncState.disabled) {
      _told = _toldLong = false;
    }
    if (sync.waitsForSettings) {
      if (!_told && _say('Sync stopped: the server refused the access token')) {
        _told = _toldLong = true;
      }
    } else if (_failingLong && !_toldLong) {
      _toldLong = _say(notSyncedSince(sync));
    }
  }

  /// Shows [message] with Settings; false if there is nowhere to yet.
  bool _say(String message) {
    final context = messenger.currentContext;
    final state = messenger.currentState;
    if (context == null || state == null) return false;
    MessageQueue.show(
      state,
      appSnackBar(
        context,
        message,
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
    return true;
  }

  void dispose() => sync.removeListener(_changed);
}
