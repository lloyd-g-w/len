import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'file_export_native.dart' show freshExportDir;
import 'print_document_api.dart';

/// Android's print framework (`PrintPlugin.kt`).
const _channel = MethodChannel('len/print');

/// A line for the print sheet where Print can't open a print dialog itself
/// (Linux: the PDF opens in the default viewer, which prints), else null.
String? get printNote => defaultTargetPlatform == TargetPlatform.linux
    ? 'Opens in your PDF viewer to print from there'
    : null;

/// Prints the PDF [bytes] of [pages] pages, named [name] (the file's and
/// the print job's name). Android: the system's print dialog. Windows: the
/// default PDF reader's print command, else the PDF opens in it. Linux and
/// elsewhere: the PDF opens in the default viewer (GTK's print dialog
/// would need a printer that takes PDFs, and `lp` prints with no choices
/// at all; a viewer previews and prints anything). Throws if nothing could
/// take the file.
Future<PrintHandoff> printPdf(Uint8List bytes, {required String name, required int pages}) async {
  final path = await _write(bytes, name);
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      await _channel.invokeMethod<void>('print', {'path': path, 'name': name, 'pages': pages});
      return PrintHandoff.dialog;
    case TargetPlatform.windows:
      if (_shellExecute('print', path)) return PrintHandoff.reader;
      await _open(path);
      return PrintHandoff.viewer;
    default:
      await _open(path);
      return PrintHandoff.viewer;
  }
}

/// Writes [bytes] as [name] into a folder of its own among the temporary
/// exports (a second print of the same notebook never overwrites a file
/// the first is still reading; old ones are cleared after an hour, and
/// Android's adapter deletes its own when the dialog closes).
Future<String> _write(Uint8List bytes, String name) async {
  final exports = await freshExportDir(await getTemporaryDirectory());
  final dir = await Directory(
    p.join(exports.path, 'print-${DateTime.now().microsecondsSinceEpoch}'),
  ).create();
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Opens [path] with the default app; throws if none could.
Future<void> _open(String path) async {
  if (!await launchUrl(Uri.file(path))) throw StateError('No app opens $path');
}

typedef _ShellExecuteC =
    IntPtr Function(
      IntPtr hwnd,
      Pointer<Utf16> verb,
      Pointer<Utf16> file,
      Pointer<Utf16> parameters,
      Pointer<Utf16> directory,
      Int32 show,
    );
typedef _ShellExecuteDart =
    int Function(
      int hwnd,
      Pointer<Utf16> verb,
      Pointer<Utf16> file,
      Pointer<Utf16> parameters,
      Pointer<Utf16> directory,
      int show,
    );
typedef _CoInitializeExC = Int32 Function(Pointer<Void> reserved, Uint32 mode);
typedef _CoInitializeExDart = int Function(Pointer<Void> reserved, int mode);

/// Windows: runs [verb] ("print") on the file at [path] with its default
/// app; false when that app has no such command (or anything fails).
bool _shellExecute(String verb, String path) {
  try {
    // Shell extensions may use COM; already set up on the runner's thread
    // (then this is a no-op answering S_FALSE or RPC_E_CHANGED_MODE).
    DynamicLibrary.open('ole32.dll').lookupFunction<_CoInitializeExC, _CoInitializeExDart>(
      'CoInitializeEx',
    )(nullptr, 0x2 /* COINIT_APARTMENTTHREADED */);
    final run = DynamicLibrary.open(
      'shell32.dll',
    ).lookupFunction<_ShellExecuteC, _ShellExecuteDart>('ShellExecuteW');
    return using((arena) {
      // Values up to 32 are errors (SE_ERR_NOASSOC: no print command).
      final code = run(
        0,
        verb.toNativeUtf16(allocator: arena),
        path.toNativeUtf16(allocator: arena),
        nullptr,
        p.dirname(path).toNativeUtf16(allocator: arena),
        1, // SW_SHOWNORMAL
      );
      if (code <= 32) debugPrint('ShellExecute $verb failed ($code) for $path');
      return code > 32;
    });
  } on Object catch (e) {
    debugPrint('ShellExecute $verb failed for $path: $e');
    return false;
  }
}
