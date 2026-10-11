import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'incoming_args.dart';

/// Channel to `IncomingFiles.kt` (Android).
const String incomingFilesChannel = 'len/incoming_files';

/// Batches of files handed to the app: on Android from intents, on
/// desktops once, from the command-line [args] (existing files only).
Stream<List<XFile>> openIncomingFiles(List<String> args) {
  if (Platform.isAndroid) return _android();
  final files = [
    for (final path in incomingPathsFromArgs(args, windows: Platform.isWindows))
      if (File(path).existsSync()) XFile(File(path).absolute.path),
  ];
  return files.isEmpty ? const Stream.empty() : Stream.value(files);
}

/// Receives `files` calls (lists of `{path, name, mime}`) once Dart says
/// it is `ready`; files of the launch intent arrive first.
Stream<List<XFile>> _android() {
  final controller = StreamController<List<XFile>>();
  const channel = MethodChannel(incomingFilesChannel);
  channel.setMethodCallHandler((call) async {
    if (call.method != 'files') return;
    final files = [
      for (final entry in (call.arguments as List<Object?>).cast<Map<Object?, Object?>>())
        XFile(
          entry['path']! as String,
          name: entry['name'] as String?,
          mimeType: entry['mime'] as String?,
        ),
    ];
    controller.add(files);
  });
  channel.invokeMethod<void>('ready').catchError((Object e) {
    debugPrint('Incoming files unavailable: $e');
  });
  return controller.stream;
}
