import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'stylus_buttons.dart';

/// Hides the system's own stylus hover pointer (the S Pen's dot, Android's
/// stylus pointer) wherever a canvas draws its own hover preview, so the two
/// don't overlap; everywhere else the system pointer shows as usual.
///
/// Flutter's mouse cursor (`SystemMouseCursors.none` over a preview) does
/// not reach a stylus on Android: the view's pointer icon applies to mice
/// only. So the canvas tells this class, for each stylus hover it handles,
/// whether it previews there ([claim], from the same decision that sets the
/// canvas's cursor); a global route of the gesture binding, which sees
/// every pointer event after the widgets under it, then says [hidden] for
/// a hover a canvas claimed with a preview and shown for any other (the
/// toolbar, menus, other screens, a canvas whose tool shows none). A tool
/// picked while the pen rests re-claims the last hover ([claim] of the
/// newest hover event), so the pointer follows at once.
///
/// Changes go to Android's `StylusPointer.kt` on `len/stylus_pointer`
/// ([send]; elsewhere nothing: there the cursor covers it). Tests feed
/// [handleEvent] directly.
class StylusPointer {
  StylusPointer({void Function(bool hidden)? send}) : _send = send ?? _defaultSend;

  final void Function(bool hidden) _send;

  static const _channel = BasicMessageChannel<Object?>(
    'len/stylus_pointer',
    StandardMessageCodec(),
  );

  static void _defaultSend(bool hidden) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.send(hidden).ignore();
  }

  PointerRouter? _router;

  /// The newest stylus hover the app saw (untransformed), and the hover a
  /// canvas last claimed with whether it previews there.
  PointerEvent? _last;
  PointerEvent? _claimed;
  bool _claimedHidden = false;

  /// Whether the system's stylus pointer is hidden now.
  bool get hidden => _hidden;
  bool _hidden = false;

  /// Starts watching the app's pointer events.
  void attach([PointerRouter? router]) {
    if (_router != null) return;
    _router = router ?? GestureBinding.instance.pointerRouter;
    _router!.addGlobalRoute(handleEvent);
  }

  /// Stops watching; the system pointer shows again.
  void detach() {
    _router?.removeGlobalRoute(handleEvent);
    _router = null;
    _last = null;
    _claimed = null;
    _set(false);
  }

  /// A canvas handled the stylus hover [e]: [preview] says whether it draws
  /// its own preview there (and hides its cursor). For the newest hover (a
  /// tool change while the pen rests) the pointer follows at once; for one
  /// still being dispatched, once it reaches [handleEvent].
  void claim(PointerEvent e, {required bool preview}) {
    final event = e.original ?? e;
    _claimed = event;
    _claimedHidden = preview;
    if (identical(event, _last)) _set(preview);
  }

  /// Sees every pointer event (after the widgets it hit).
  void handleEvent(PointerEvent e) {
    if (!isStylusKind(e.kind) || e is! PointerHoverEvent) return;
    final event = e.original ?? e;
    _last = event;
    _set(identical(event, _claimed) && _claimedHidden);
  }

  void _set(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    _send(value);
  }
}
