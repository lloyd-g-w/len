import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';

/// Focus mode's way out (REDESIGN §2.7): a small 32-dp button in the
/// corner, at 40 % opacity until hovered or touched, that brings the
/// toolbar and top bar back. (The tools stay at hand in the `ToolPuck`.)
class FocusHandle extends StatefulWidget {
  const FocusHandle({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  State<FocusHandle> createState() => _FocusHandleState();
}

class _FocusHandleState extends State<FocusHandle> {
  bool _near = false;

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
          opacity: _near ? 1 : 0.4,
          duration: Motion.fast,
          child: Tooltip(
            message: 'Show toolbars (F11)',
            // 32 dp to see, but a full 40-dp target around it.
            child: Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onExit,
                child: SizedBox.square(
                  dimension: Targets.bar,
                  child: Center(
                    child: FloatingPanel(
                      radius: Radii.pill,
                      padding: EdgeInsets.zero,
                      child: SizedBox.square(
                        dimension: 32,
                        child: Icon(
                          Symbols.fullscreen_exit_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
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
