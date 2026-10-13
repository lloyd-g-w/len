import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The marker file in the app's data [directory].
File _marker(String directory) => File(p.join(directory, 'install-marker'));

/// Whether this platform keeps an install marker.
const bool hasInstallMarker = true;

/// The marker's content, or null if there is none (or it can't be read).
String? readInstallMarker(String directory) {
  try {
    final file = _marker(directory);
    return file.existsSync() ? file.readAsStringSync().trim() : null;
  } on FileSystemException {
    return null;
  }
}

/// Writes [deviceId] into the marker (best effort: without it, the next
/// start only takes a new device id once more).
void writeInstallMarker(String directory, String deviceId) {
  try {
    _marker(directory).writeAsStringSync(deviceId, flush: true);
  } on FileSystemException catch (e) {
    debugPrint('Cannot write the install marker: $e');
  }
}
