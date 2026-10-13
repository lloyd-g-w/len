import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../data/write_back.dart';

/// Flushes [writes] when the tab is hidden (switching tabs or apps, and
/// before closing) or the page is hidden for good (`pagehide`), retries a
/// failed write when the tab is shown again, and keeps a `beforeunload`
/// guard (the browser's "Leave site?") only while a write is pending, so
/// closing the tab right after an edit doesn't lose it, and idle pages stay
/// eligible for the back/forward cache.
void watchPageLifecycle(StorageWrites writes) {
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.hidden || writes.failure != null) unawaited(writes.flush());
    }).toJS,
  );
  web.window.addEventListener('pagehide', ((web.Event _) => unawaited(writes.flush())).toJS);

  final guard = ((web.BeforeUnloadEvent event) {
    unawaited(writes.flush());
    event.preventDefault();
    event.returnValue = ''; // Older browsers need it set.
  }).toJS;
  var guarding = false;
  void update() {
    if (writes.pending == guarding) return;
    guarding = writes.pending;
    if (guarding) {
      web.window.addEventListener('beforeunload', guard);
    } else {
      web.window.removeEventListener('beforeunload', guard);
    }
  }

  writes.addListener(update);
  update();
}
