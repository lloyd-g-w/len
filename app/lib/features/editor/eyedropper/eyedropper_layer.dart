import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import 'eyedropper_loupe.dart';
import 'page_colours.dart';
import 'page_snapshot.dart';

/// The eyedropper's layer over the whole app while it waits for a pick: it
/// takes every pointer (nothing draws, scrolls or opens meanwhile), shows
/// the hint "Tap a colour on the page" and, while a pointer presses or
/// hovers on the page, the [EyedropperLoupe]. Lifting a pointer pressed on
/// the page picks the colour there; a press anywhere else (chrome, menus,
/// the desk between pages) or Escape cancels; a palm near the pen is
/// ignored. Reports once through
/// [onDone]: the colour, or null when cancelled.
class EyedropperLayer extends StatefulWidget {
  const EyedropperLayer({super.key, required this.colours, required this.onDone});

  final PageColours colours;
  final ValueChanged<int?> onDone;

  /// The hint.
  static const String hint = 'Tap a colour on the page';

  @override
  State<EyedropperLayer> createState() => _EyedropperLayerState();
}

class _EyedropperLayerState extends State<EyedropperLayer> {
  PageSnapshot? _snapshot;

  /// The pointer pressed on the page, until it lifts.
  int? _pointer;

  /// Where the loupe looks (global); null hides it.
  Offset? _at;

  /// The colour at [_at], once read; [_reads] drops stale reads.
  int? _colour;
  int _reads = 0;

  bool _done = false;

  PageColours get _colours => widget.colours;

  @override
  void initState() {
    super.initState();
    final boundary = _colours.canvas.currentContext?.findRenderObject();
    if (boundary is RenderRepaintBoundary) {
      final dpr = WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ?? 1;
      PageSnapshot.capture(boundary, dpr).then((shot) {
        if (!mounted) return shot?.dispose();
        setState(() => _snapshot = shot);
        if (_at case final at?) _look(at);
      });
    }
  }

  @override
  void dispose() {
    _snapshot?.dispose();
    super.dispose();
  }

  void _finish(int? colour) {
    if (_done) return;
    _done = true;
    widget.onDone(colour);
  }

  /// Points the loupe at [global], or hides it off the page.
  void _look(Offset global) {
    if (!_colours.onPage(global)) {
      setState(() => _at = null);
      return;
    }
    final read = ++_reads;
    setState(() => _at = global);
    _colours.colourAt(global, snapshot: _snapshot, dpr: _snapshot?.dpr ?? 1).then((c) {
      if (mounted && read == _reads) setState(() => _colour = c);
    });
  }

  void _down(PointerDownEvent event) {
    // A palm landing near the pen neither picks nor cancels.
    if (_pointer != null || _done || _colours.isPalm(event)) return;
    final primary = event.kind != PointerDeviceKind.mouse || event.buttons == kPrimaryButton;
    if (!primary || !_colours.onPage(event.position)) return _finish(null);
    _pointer = event.pointer;
    _look(event.position);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer == _pointer) _look(event.position);
  }

  Future<void> _up(PointerUpEvent event) async {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final at = event.position;
    if (!_colours.onPage(at)) return _finish(null);
    _reads++; // The loupe's read in flight no longer matters.
    _finish(await _colours.colourAt(at, snapshot: _snapshot, dpr: _snapshot?.dpr ?? 1));
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    setState(() => _at = null);
  }

  void _hover(PointerHoverEvent event) {
    if (_pointer == null) _look(event.position);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _finish(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final free = _colours.free ?? (Offset.zero & MediaQuery.sizeOf(context));
    final at = _at;
    final right = at != null && at.dx < free.center.dx;
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          onExit: (_) {
            if (_pointer == null) setState(() => _at = null);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            onPointerHover: _hover,
            child: Stack(
              children: [
                Positioned(
                  left: free.left + Gaps.md,
                  right: MediaQuery.sizeOf(context).width - free.right + Gaps.md,
                  top: free.top + Gaps.md,
                  child: IgnorePointer(
                    child: Column(
                      crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        const Align(child: _Hint()),
                        if (at != null) ...[
                          const SizedBox(height: Gaps.sm),
                          EyedropperLoupe(snapshot: _snapshot, at: at, colour: _colour),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: FloatingPanel(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.colorize_sharp,
              size: Glyphs.menu,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Gaps.sm),
            Flexible(child: Text(EyedropperLayer.hint, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
