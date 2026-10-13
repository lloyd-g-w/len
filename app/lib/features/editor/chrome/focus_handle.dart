import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';

/// Focus mode's way out (REDESIGN §2.7): a small 32-dp button in the
/// corner that brings the toolbar and top bar back. (The tools stay at hand
/// in the `ToolPuck`.) It shows in full for [announce] after focus mode
/// starts, then rests at [restingOpacity] until hovered or touched; touch
/// has no hover, so it rests firmer there.
class FocusHandle extends StatefulWidget {
  const FocusHandle({super.key, required this.onExit, this.active = true});

  final VoidCallback onExit;

  /// Whether focus mode is on (the handle shows); turning it on announces
  /// the handle.
  final bool active;

  /// How long the handle shows in full when focus mode starts.
  static const Duration announce = Duration(seconds: 2);

  /// The handle's opacity at rest: 0.7 on touch, 0.4 with a pointer.
  static double get restingOpacity => Targets.touchFirst ? 0.7 : 0.4;

  @override
  State<FocusHandle> createState() => _FocusHandleState();
}

class _FocusHandleState extends State<FocusHandle> {
  bool _near = false;
  Timer? _announcing;

  @override
  void initState() {
    super.initState();
    if (widget.active) _announce();
  }

  @override
  void didUpdateWidget(FocusHandle old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _announce();
  }

  @override
  void dispose() {
    _announcing?.cancel();
    super.dispose();
  }

  void _announce() {
    _announcing?.cancel();
    _announcing = Timer(FocusHandle.announce, () => setState(() => _announcing = null));
  }

  void _set(bool near) {
    if (near != _near) setState(() => _near = near);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedOpacity(
          opacity: _near || _announcing != null ? 1 : FocusHandle.restingOpacity,
          duration: Motion.fast,
          child: Tooltip(
            message: 'Show toolbars (F11)',
            // 32 dp to see, but a full bar target around it.
            child: Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onExit,
                child: SizedBox.square(
                  dimension: Targets.barHit(context),
                  child: Center(
                    child: FloatingPanel(
                      radius: Radii.pill,
                      padding: EdgeInsets.zero,
                      child: SizedBox.square(
                        dimension: 32,
                        child: Icon(
                          Symbols.fullscreen_exit_rounded,
                          size: 18,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hides the system bars too (Android) in focus mode, for a truly
/// distraction-free page; [on] false shows them again.
void setImmersive(bool on) => unawaited(
  on
      ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
      : SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values),
);
