import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_export_api.dart';

bool get _mobile =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Android's system save dialogs (`SaveDocumentPlugin.kt`).
const _saveChannel = MethodChannel('len/save_document');

/// Whether exports can also be saved through the system's save dialog
/// besides sharing (Android: "Save to device").
bool get canSaveToDevice => defaultTargetPlatform == TargetPlatform.android;

/// Whether [showInFolder] works here (desktops).
bool get canShowInFolder =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Desktop: asks where to save and writes the file. Mobile: opens the share
/// sheet, or with [toDevice] (Android) the system's save dialog. Null if
/// cancelled.
Future<ExportedFiles?> saveOrShare(
  Uint8List bytes, {
  required String name,
  required String mime,
  bool toDevice = false,
}) async {
  if (_mobile) return _mobileExport([(bytes: bytes, name: name)], mime, toDevice: toDevice);
  final extension = p.extension(name).replaceFirst('.', '');
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: extension.toUpperCase(), extensions: [extension], mimeTypes: [mime]),
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes, flush: true);
  return ExportedFiles(
    ExportedTo.file,
    count: 1,
    name: p.basename(location.path),
    path: location.path,
  );
}

/// Like [saveOrShare] for several [files] of one [mime] type. Mobile:
/// shares (or saves) them all at once. Desktop: one file gets a save
/// dialog, several go into a folder the user picks (never overwriting a
/// file there).
Future<ExportedFiles?> saveOrShareAll(
  List<({Uint8List bytes, String name})> files, {
  required String mime,
  bool toDevice = false,
}) async {
  final single = files.length == 1 ? files.single : null;
  if (single != null) {
    return saveOrShare(single.bytes, name: single.name, mime: mime, toDevice: toDevice);
  }
  if (_mobile) return _mobileExport(files, mime, toDevice: toDevice);
  final dir = await getDirectoryPath(confirmButtonText: 'Save here');
  if (dir == null) return null;
  for (final f in files) {
    await File(_freePath(dir, f.name)).writeAsBytes(f.bytes, flush: true);
  }
  return ExportedFiles(ExportedTo.folder, count: files.length, name: p.basename(dir), path: dir);
}

/// Writes [files] to a temporary folder, then opens the share sheet or
/// (with [toDevice]) the system's save dialog.
Future<ExportedFiles?> _mobileExport(
  List<({Uint8List bytes, String name})> files,
  String mime, {
  required bool toDevice,
}) async {
  final tmp = await getTemporaryDirectory();
  final dir = await Directory(p.join(tmp.path, 'export')).create(recursive: true);
  final paths = <String>[];
  for (final f in files) {
    final file = File(p.join(dir.path, f.name));
    await file.writeAsBytes(f.bytes, flush: true);
    paths.add(file.path);
  }
  return _mobileShare(paths, [for (final f in files) f.name], mime, toDevice: toDevice);
}

/// Opens the share sheet for the files at [paths] (named [names]), or with
/// [toDevice] the system's save dialog.
Future<ExportedFiles?> _mobileShare(
  List<String> paths,
  List<String> names,
  String mime, {
  required bool toDevice,
}) async {
  final single = names.length == 1 ? names.single : null;
  if (toDevice && canSaveToDevice) {
    // The name of the file (one) or folder (several) chosen; null if
    // cancelled.
    final saved = await _saveChannel.invokeMethod<String>('save', {
      'paths': paths,
      'names': names,
      'mime': mime,
    });
    if (saved == null) return null;
    return ExportedFiles(
      single == null ? ExportedTo.folder : ExportedTo.device,
      count: names.length,
      name: saved,
    );
  }
  final result = await SharePlus.instance.share(
    ShareParams(files: [for (final path in paths) XFile(path, mimeType: mime)]),
  );
  if (result.status == ShareResultStatus.dismissed) return null;
  return ExportedFiles(ExportedTo.shared, count: names.length, name: single);
}

/// Desktop: asks where to save a file named [name] (before writing it,
/// so a long export never ends in a dialog); the chosen path, or null if
/// cancelled.
Future<String?> askSaveLocation(String name, {required String mime}) async {
  final extension = p.extension(name).replaceFirst('.', '');
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: extension.toUpperCase(), extensions: [extension], mimeTypes: [mime]),
    ],
  );
  return location?.path;
}

/// Mobile: shares the file written at [path] (too large to hold in memory,
/// e.g. a library backup), or with [toDevice] (Android) saves it through
/// the system's save dialog. Null if cancelled.
Future<ExportedFiles?> shareFile(
  String path, {
  required String name,
  required String mime,
  bool toDevice = false,
}) => _mobileShare([path], [name], mime, toDevice: toDevice);

/// Opens the file manager at [path] (a file: selected where the file
/// manager allows; a folder: opened). Desktops only; never throws.
Future<void> showInFolder(String path) async {
  final isDir = FileSystemEntity.isDirectorySync(path);
  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        await Process.start('explorer.exe', [if (isDir) path else '/select,$path']);
      case TargetPlatform.macOS:
        await Process.start('open', [if (!isDir) '-R', path]);
      default:
        // Most Linux file managers select the file through this D-Bus call.
        final shown = isDir
            ? null
            : await Process.run('dbus-send', [
                '--session',
                '--print-reply',
                '--dest=org.freedesktop.FileManager1',
                '/org/freedesktop/FileManager1',
                'org.freedesktop.FileManager1.ShowItems',
                'array:string:${Uri.file(path)}',
                'string:',
              ]);
        if (shown?.exitCode != 0) {
          await Process.start('xdg-open', [isDir ? path : p.dirname(path)]);
        }
    }
  } on Object catch (e) {
    debugPrint('Cannot show $path in its folder: $e');
  }
}

/// `dir/name`, or `dir/name (2).ext`… if that file exists.
String _freePath(String dir, String name) {
  var path = p.join(dir, name);
  for (var n = 2; File(path).existsSync(); n++) {
    path = p.join(dir, '${p.basenameWithoutExtension(name)} ($n)${p.extension(name)}');
  }
  return path;
}
