import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';

/// The only chrome left in focus mode: a small, translucent button that
/// brings the toolbar and top bar back.
class FocusHandle extends StatelessWidget {
  const FocusHandle({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Show toolbars (F11)',
      child: FloatingPanel(
        radius: Radii.pill,
        padding: EdgeInsets.zero,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onExit,
          child: Padding(
            padding: const EdgeInsets.all(Gaps.sm + 2),
            child: Icon(Symbols.fullscreen_exit_rounded, size: 22, color: scheme.onSurfaceVariant),
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
