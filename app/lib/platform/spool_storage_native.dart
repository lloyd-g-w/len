import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../data/spool_storage.dart';
import 'app_directory_native.dart';

/// Opens `<app support>/recording`, where recordings in progress are
/// written.
Future<SpoolStorage?> openRecordingSpool() async {
  final dir = Directory(p.join(await appDataDirectory(), 'recording'));
  await dir.create(recursive: true);
  return FileSpoolStorage(dir.path);
}

/// [SpoolStorage] in a directory.
class FileSpoolStorage implements SpoolStorage {
  FileSpoolStorage(this.directory);

  final String directory;

  @override
  String pathOf(String name) => p.join(directory, name);

  @override
  Future<List<String>> list() async => [
    for (final entry in Directory(directory).listSync())
      if (entry is File && !entry.path.endsWith('.tmp')) p.basename(entry.path),
  ];

  @override
  Future<Uint8List?> read(String name) async {
    final file = File(pathOf(name));
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    final temp = File('${pathOf(name)}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(pathOf(name));
  }

  @override
  Future<void> delete(String name) async {
    try {
      await File(pathOf(name)).delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
