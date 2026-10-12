import 'package:web/web.dart' as web;

/// The browser's `(pointer: coarse)` media query (phones and tablets).
bool get primaryPointerIsCoarse => web.window.matchMedia('(pointer: coarse)').matches;
