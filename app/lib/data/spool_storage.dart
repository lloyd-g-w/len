import 'dart:typed_data';

/// A directory for work in progress that must survive the app being
/// killed: the files of a recording being made and its journal (see
/// `RecordingSpool`). Files under `<app support>/recording` natively
/// (`platform/spool_storage_native.dart`); browsers have none (their
/// recorder hands out audio only when it stops); memory in tests.
abstract interface class SpoolStorage {
  /// Where file [name] is (a recorder writes it there itself).
  String pathOf(String name);

  /// Names of the files present.
  Future<List<String>> list();

  /// File [name]'s bytes, or null if there is none.
  Future<Uint8List?> read(String name);

  /// Replaces file [name] with [bytes] atomically (a crash leaves the old
  /// or the new contents, never a mix).
  Future<void> write(String name, Uint8List bytes);

  /// Deletes file [name] (a no-op if there is none).
  Future<void> delete(String name);
}

/// [SpoolStorage] in memory, for tests: a "recorder" writes a file by
/// [write]-ing to it.
class MemorySpoolStorage implements SpoolStorage {
  final Map<String, Uint8List> files = {};

  @override
  String pathOf(String name) => 'spool/$name';

  @override
  Future<List<String>> list() async => files.keys.toList();

  @override
  Future<Uint8List?> read(String name) async => files[name];

  @override
  Future<void> write(String name, Uint8List bytes) async => files[name] = bytes;

  @override
  Future<void> delete(String name) async => files.remove(name);
}
