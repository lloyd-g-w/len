import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:web/web.dart' as web;

import 'tab_handover.dart';

const _name = 'len-database';

/// Coordinates Len's tabs with a Web Lock and a BroadcastChannel; null in
/// browsers without Web Locks (very old ones). `flutter_bootstrap.js` sets
/// `window.lenTab`: this tab's id and whether it is a reload of the tab
/// holding the lock, which has already asked for it back (`take:<id>`)
/// before the app loaded.
TabHandover? openTabHandover() {
  if (!(web.window.navigator as JSObject).has('locks')) return null;
  final early = globalContext['lenTab'];
  final tab = early.isA<JSObject>() ? early as JSObject : null;
  final id = tab?['id'];
  return TabHandover(
    lock: _WebLock(web.window.navigator.locks),
    channel: _Channel(web.BroadcastChannel(_name)),
    id: id.isA<JSString>() ? (id as JSString).toDart : Random().nextInt(1 << 30).toRadixString(36),
    reclaim: tab?['reclaim'].isA<JSBoolean>() == true && (tab!['reclaim'] as JSBoolean).toDart,
    onHoldingChanged: _rememberHolding,
  );
}

/// Read by `flutter_bootstrap.js` after a reload.
const _heldKey = 'len-held';

void _rememberHolding(bool holding) {
  try {
    if (holding) {
      web.window.sessionStorage.setItem(_heldKey, '1');
    } else {
      web.window.sessionStorage.removeItem(_heldKey);
    }
  } on Object catch (_) {} // Storage blocked: reloads wait like other tabs.
}

/// Starts this tab afresh (after handing Len to another tab: it then
/// waits for its turn again).
void reloadTab() => web.window.location.reload();

class _WebLock implements TabLock {
  _WebLock(this._locks);

  final web.LockManager _locks;

  /// Completes the held lock's callback promise, which releases it.
  Completer<JSAny?>? _held;

  @override
  Future<bool> request({bool ifAvailable = false}) {
    final granted = Completer<bool>();
    JSPromise<JSAny?> callback(web.Lock? lock) {
      granted.complete(lock != null);
      if (lock == null) return Future<JSAny?>.value().toJS;
      final held = _held = Completer<JSAny?>();
      return held.future.toJS;
    }

    _locks.request(_name, web.LockOptions(ifAvailable: ifAvailable), callback.toJS);
    return granted.future;
  }

  @override
  void release() {
    _held?.complete();
    _held = null;
  }
}

class _Channel implements TabChannel {
  _Channel(this._channel);

  final web.BroadcastChannel _channel;

  @override
  void post(String message) => _channel.postMessage(message.toJS);

  @override
  set onMessage(void Function(String message) handler) {
    _channel.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data.isA<JSString>()) handler((data as JSString).toDart);
    }).toJS;
  }
}
