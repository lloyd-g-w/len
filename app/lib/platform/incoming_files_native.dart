import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'incoming_args.dart';

/// Channel to `IncomingFiles.kt` (Android) and the desktop runners (files a
/// second `len <file>` forwarded: Linux `my_application.cc`, Windows
/// `flutter_window.cpp` + `single_instance.cpp`).
const String incomingFilesChannel = 'len/incoming_files';

/// Batches of files handed to the app: on Android from intents; on
/// desktops from the command-line [args] (existing files only) and files
/// opened while Len runs. Links among the desktop [args] (`len "len://sync?…"`)
/// go to [incomingLinks].
Stream<List<XFile>> openIncomingFiles(List<String> args) {
  final controller = StreamController<List<XFile>>();
  if (!Platform.isAndroid) {
    args.where(isIncomingLink).forEach(_links.add);
    final files = [
      for (final path in incomingPathsFromArgs(args, windows: Platform.isWindows))
        if (File(path).existsSync()) XFile(File(path).absolute.path),
    ];
    if (files.isNotEmpty) controller.add(files);
  }
  _listen(controller);
  return controller.stream;
}

/// Links Len was opened with (`len://sync?…` setup links: on Android by the
/// intent filter in `AndroidManifest.xml`; on desktops on the command line,
/// also forwarded from a second `len` as a "path"), kept until listened to.
final StreamController<String> _links = StreamController<String>();
Stream<String> get incomingLinks => _links.stream;

/// Receives `files` calls (lists of `{path, name, mime}`) and `link` calls
/// (a string) once Dart says it is `ready`; on Android, those of the launch
/// intent arrive first.
void _listen(StreamController<List<XFile>> controller) {
  const channel = MethodChannel(incomingFilesChannel);
  channel.setMethodCallHandler((call) async {
    if (call.method == 'link') return _links.add(call.arguments as String);
    if (call.method != 'files') return;
    final entries = (call.arguments as List<Object?>).cast<Map<Object?, Object?>>();
    // Desktop launches forward whatever was typed after `len`: links as
    // they are, the rest as absolute paths.
    bool link(Map<Object?, Object?> e) =>
        !Platform.isAndroid && isIncomingLink(e['path']! as String);
    entries.where(link).forEach((e) => _links.add(e['path']! as String));
    final files = [
      for (final entry in entries.where((e) => !link(e)))
        if (Platform.isAndroid || File(entry['path']! as String).existsSync())
          XFile(
            entry['path']! as String,
            name: entry['name'] as String?,
            mimeType: entry['mime'] as String?,
          ),
    ];
    if (files.isNotEmpty) controller.add(files);
  });
  channel.invokeMethod<void>('ready').catchError((Object e) {
    debugPrint('Incoming files unavailable: $e');
  });
}
