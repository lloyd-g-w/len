// Writes the precache list into a web build's service worker (`sw.js`):
//   dart run tool/web_precache.dart [build/web]
// Run after every `flutter build web` (tool/build_web.sh does both). The
// list's version is a hash of every listed file, so a changed build changes
// sw.js and browsers install the new worker (see web/sw.js).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _start = '/* precache */';
const _end = '/* end precache */';

/// Whether the build file at [path] (relative, `/`-separated) is precached:
/// not the workers themselves, build metadata or debug symbols, and the
/// renderers this build never loads: skwasm / wimp only in `--wasm` builds,
/// never the WebParagraph CanvasKit (only with `preferWebParagraph`).
/// CanvasKit's full and Chromium variants both stay: the browser picks one.
bool precached(String path, {required bool wasmBuild}) {
  if (const {'sw.js', 'flutter_service_worker.js', '.last_build_id'}.contains(path)) return false;
  if (path.endsWith('.symbols') || path.endsWith('.map')) return false;
  if (path.startsWith('canvaskit/webparagraph/')) return false;
  if (!wasmBuild && RegExp(r'^canvaskit/(skwasm|wimp)').hasMatch(path)) return false;
  return true;
}

/// [source] (sw.js) with the precache list for [files] (path → bytes).
String injectPrecache(String source, Map<String, List<int>> files) {
  final start = source.indexOf(_start);
  final end = source.indexOf(_end);
  if (start < 0 || end < start) throw const FormatException('sw.js has no precache markers');
  final wasmBuild = files.containsKey('main.dart.wasm');
  final paths = files.keys.where((p) => precached(p, wasmBuild: wasmBuild)).toList()..sort();
  final digest = sha256.convert([
    for (final p in paths) ...utf8.encode('$p\n${sha256.convert(files[p]!)}\n'),
  ]);
  final list = jsonEncode({'version': digest.toString().substring(0, 16), 'files': paths});
  return '${source.substring(0, start + _start.length)} $list ${source.substring(end)}';
}

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'build/web' : args.first);
  final sw = File('${dir.path}/sw.js');
  if (!sw.existsSync()) {
    stderr.writeln('${sw.path} not found: build the web app first');
    exitCode = 1;
    return;
  }
  final files = <String, List<int>>{
    for (final f in dir.listSync(recursive: true).whereType<File>())
      f.path.substring(dir.path.length + 1).replaceAll(r'\', '/'): f.readAsBytesSync(),
  };
  sw.writeAsStringSync(injectPrecache(sw.readAsStringSync(), files));
  final count = files.keys.where(
    (p) => precached(p, wasmBuild: files.containsKey('main.dart.wasm')),
  );
  stdout.writeln('sw.js: ${count.length} files precached');
}
