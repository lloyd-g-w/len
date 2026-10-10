import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The system-bar style for a theme of [brightness]: transparent status and
/// navigation bars (the app draws edge to edge) with icons that contrast
/// with the app's surface.
SystemUiOverlayStyle systemBarsStyle(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final icons = dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: brightness, // iOS naming: the bar's background
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Draws the app edge to edge on Android and keeps the system-bar icons
/// readable in the app's light / dark theme (which may differ from the
/// system's). Screens with an [AppBar] still override this with their own
/// style. Use as `MaterialApp.builder`.
class SystemBars extends StatefulWidget {
  const SystemBars({super.key, required this.child});

  final Widget child;

  @override
  State<SystemBars> createState() => _SystemBarsState();
}

class _SystemBarsState extends State<SystemBars> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: systemBarsStyle(Theme.of(context).brightness),
    child: widget.child,
  );
}
