import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/cancellation.dart';
import '../blob_store.dart';
import '../syncable_table.dart';
import 'len_archive_reader.dart';
import 'len_archive_writer.dart';
import 'len_format.dart';
import 'len_scope.dart';
import 'len_stores.dart';

export 'len_archive_reader.dart' show LenImportResult;
export 'len_archive_writer.dart' show BlobFileOpener, LenWriteReport;
export 'len_format.dart';
export 'len_scope.dart' show LenScope;

/// Writes and reads Len files ([LenFormat]) of this library; notifies
/// listeners (the library) after an import added something.
class LenArchives extends ChangeNotifier {
  LenArchives({
    required Iterable<SyncableTable> tables,
    required this.blobs,
    required this.deviceId,
    this.openBlobFile,
    this.clock = const Clock(),
  }) : stores = LenStores(tables);

  final LenStores stores;
  final BlobStore blobs;
  final String deviceId;

  /// Reads blob files in chunks where the platform has files.
  BlobFileOpener? openBlobFile;
  final Clock clock;

  /// Writes [scope] into [output] (see [LenArchiveWriter.write]).
  Future<LenWriteReport> write(
    LenScope scope,
    OutputStream output, {
    CancellationToken? cancel,
    void Function(double done)? onProgress,
  }) => LenArchiveWriter(
    stores,
    blobs,
    openBlobFile: openBlobFile,
    clock: clock,
  ).write(scope, output, cancel: cancel, onProgress: onProgress);

  /// Imports [input] as a copy (see [LenArchiveReader.import]).
  Future<LenImportResult> import(
    InputStream input, {
    String? parent,
    String? Function(LenManifest manifest)? folderName,
    int folderColor = 0,
    CancellationToken? cancel,
    void Function(double done)? onProgress,
  }) async {
    final result = await LenArchiveReader(stores, blobs, deviceId: deviceId, clock: clock).import(
      input,
      parent: parent,
      folderName: folderName,
      folderColor: folderColor,
      cancel: cancel,
      onProgress: onProgress,
    );
    notifyListeners();
    return result;
  }
}
