import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Desktop: asks where to save and returns the path (null if cancelled).
/// Mobile: opens the share sheet and returns null.
Future<String?> saveOrShare(Uint8List bytes, {required String name, required String mime}) async {
  final mobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (mobile) {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)]));
    return null;
  }
  final extension = p.extension(name).replaceFirst('.', '');
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: extension.toUpperCase(), extensions: [extension], mimeTypes: [mime]),
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes, flush: true);
  return location.path;
}
