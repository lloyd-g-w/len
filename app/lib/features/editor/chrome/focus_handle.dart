import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_theme.dart';

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
      child: Material(
        color: scheme.surfaceContainer.withValues(alpha: 0.82),
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onExit,
          child: Padding(
            padding: const EdgeInsets.all(Gaps.sm + 2),
            child: Icon(Icons.fullscreen_exit_rounded, size: 22, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Hides the system bars too (Android) in focus mode, for a truly
/// distraction-free page; [on] false brings them back.
void setImmersive(bool on) => unawaited(
  SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge),
);
