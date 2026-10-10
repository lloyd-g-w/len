import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _lockName = 'len-database';

/// Holds an exclusive Web Lock for as long as this tab lives. If another
/// tab holds it, calls [onWaiting] and completes once that tab is closed.
Future<void> claimSingleInstance({required void Function() onWaiting}) async {
  if (!(web.window.navigator as JSObject).has('locks')) return; // Very old browser.
  final locks = web.window.navigator.locks;
  if (await _request(locks, web.LockOptions(ifAvailable: true))) return;
  onWaiting();
  await _request(locks, web.LockOptions());
}

/// Requests the lock; completes with whether it was granted (only
/// `ifAvailable` requests can be refused). Once granted, it is never
/// released: the browser releases it when the tab closes.
Future<bool> _request(web.LockManager locks, web.LockOptions options) {
  final granted = Completer<bool>();
  JSPromise<JSAny?> callback(web.Lock? lock) {
    granted.complete(lock != null);
    return lock == null ? Future<JSAny?>.value().toJS : Completer<JSAny?>().future.toJS;
  }

  locks.request(_lockName, options, callback.toJS);
  return granted.future;
}
