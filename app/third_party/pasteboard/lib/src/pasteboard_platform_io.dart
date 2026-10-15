import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pasteboard_platform.dart';

const PasteboardPlatform pasteboard = PasteboardPlatformIO();

class PasteboardPlatformIO implements PasteboardPlatform {
  const PasteboardPlatformIO();

  static const MethodChannel _channel = MethodChannel('pasteboard');

  @override
  Future<List<String>> files() async {
    final files = await _channel.invokeMethod<List>('files');
    return files?.cast<String>() ?? const [];
  }

  @override
  Future<String?> get html async {
    if (Platform.isWindows || Platform.isAndroid) {
      return await _channel.invokeMethod<Object>('html') as String?;
    }
    if (Platform.isLinux) {
      final bytes = await _channel.invokeMethod<Uint8List>('html');
      return bytes == null ? null : decodeHtmlBytes(bytes);
    }
    return null;
  }

  @override
  Future<Uint8List?> get image async {
    final image = await _channel.invokeMethod<Object>('image');

    if (image == null) {
      return null;
    }
    if (Platform.isMacOS || Platform.isLinux || Platform.isIOS || Platform.isAndroid) {
      return image as Uint8List;
    } else if (Platform.isWindows) {
      final file = File(image as String);
      final bytes = await file.readAsBytes();
      await file.delete();
      return bytes;
    }
    return null;
  }

  @override
  Future<bool> writeFiles(List<String> files) async {
    try {
      await _channel.invokeMethod<Object>('writeFiles', files);
      return true;
    } catch (error, stacktrace) {
      debugPrint('$error\n$stacktrace');
      return false;
    }
  }

  @override
  Future<void> writeImage(Uint8List? image) async {
    if (image == null) {
      return;
    }
    if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
      await _channel.invokeMethod<void>('writeImage', image);
    } else if (Platform.isWindows) {
      final file = await File(_getTempFileName()).create();
      file.writeAsBytesSync(image);
      await _channel
          .invokeMethod<Object>('writeImage', {'fileName': file.path});
      file.delete();
    }
  }

  @override
  Future<bool> write({Future<Uint8List?>? png, String? text}) async {
    if (!(Platform.isAndroid || Platform.isLinux || Platform.isWindows)) return false;
    try {
      final image = await png;
      if (image == null && text == null) return false;
      final done = await _channel.invokeMethod<bool>('write', {
        if (image != null) 'png': image,
        if (text != null) 'text': text,
      });
      return done ?? false;
    } catch (error) {
      debugPrint('Writing the clipboard failed: $error');
      return false;
    }
  }

  @override
  Future<String?> get text async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  void writeText(String value) {
    Clipboard.setData(ClipboardData(text: value));
  }
}

String _getTempFileName() {
  final dir = Directory.systemTemp;
  String tempFileName;

  const uuid = Uuid();

  while (true) {
    tempFileName = p.join(dir.path, uuid.v1().toString());
    if (!File(tempFileName).existsSync()) {
      break;
    }
  }

  return tempFileName;
}

/// HTML bytes from the X11 / Wayland clipboard: UTF-16 with a byte order
/// mark or (no mark, but a zero high byte first) little-endian UTF-16
/// (Firefox), else UTF-8.
@visibleForTesting
String decodeHtmlBytes(Uint8List bytes) {
  final le = bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE;
  if (le || (bytes.length >= 2 && bytes[0] != 0 && bytes[1] == 0)) {
    return String.fromCharCodes([
      for (var i = le ? 2 : 0; i + 1 < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
    ]);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return String.fromCharCodes([
      for (var i = 2; i + 1 < bytes.length; i += 2) bytes[i] << 8 | bytes[i + 1],
    ]);
  }
  return utf8.decode(bytes, allowMalformed: true);
}
