import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

bool get _mobile =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Desktop: asks where to save and returns the path (null if cancelled).
/// Mobile: opens the share sheet and returns null.
Future<String?> saveOrShare(Uint8List bytes, {required String name, required String mime}) async {
  if (_mobile) return _share([(bytes: bytes, name: name)], mime);
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

/// Like [saveOrShare] for several [files] of one [mime] type. Mobile:
/// shares them all at once. Desktop: one file gets a save dialog, several
/// go into a folder the user picks (never overwriting a file there); the
/// folder's path is returned (null if cancelled).
Future<String?> saveOrShareAll(
  List<({Uint8List bytes, String name})> files, {
  required String mime,
}) async {
  final single = files.length == 1 ? files.single : null;
  if (single != null) return saveOrShare(single.bytes, name: single.name, mime: mime);
  if (_mobile) return _share(files, mime);
  final dir = await getDirectoryPath(confirmButtonText: 'Save here');
  if (dir == null) return null;
  for (final f in files) {
    await File(_freePath(dir, f.name)).writeAsBytes(f.bytes, flush: true);
  }
  return dir;
}

/// Writes [files] to a temporary folder and opens the share sheet.
Future<String?> _share(List<({Uint8List bytes, String name})> files, String mime) async {
  final tmp = await getTemporaryDirectory();
  final dir = await Directory(p.join(tmp.path, 'export')).create(recursive: true);
  final shared = <XFile>[];
  for (final f in files) {
    final file = File(p.join(dir.path, f.name));
    await file.writeAsBytes(f.bytes, flush: true);
    shared.add(XFile(file.path, mimeType: mime));
  }
  await SharePlus.instance.share(ShareParams(files: shared));
  return null;
}

/// `dir/name`, or `dir/name (2).ext`… if that file exists.
String _freePath(String dir, String name) {
  var path = p.join(dir, name);
  for (var n = 2; File(path).existsSync(); n++) {
    path = p.join(dir, '${p.basenameWithoutExtension(name)} ($n)${p.extension(name)}');
  }
  return path;
}
