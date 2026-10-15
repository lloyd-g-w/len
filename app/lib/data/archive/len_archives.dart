import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/cancellation.dart';
import '../blob_references.dart';
import '../blob_store.dart';
import '../syncable_table.dart';
import 'len_archive_reader.dart';
import 'len_archive_writer.dart';
import 'len_format.dart';
import 'len_import_result.dart';
import 'len_scope.dart';
import 'len_source.dart';
import 'len_stores.dart';

export 'len_archive_writer.dart' show BlobFetcher, BlobFileChecksum, BlobFileOpener, LenWriteReport;
export 'len_format.dart';
export 'len_import_result.dart';
export 'len_scope.dart' show LenScope;
export 'len_source.dart' show LenSource;

/// Writes and reads Len files ([LenFormat]) of this library; notifies
/// listeners (the library, Settings → Backup) after an import added
/// something or a library backup was made.
class LenArchives extends ChangeNotifier {
  LenArchives({
    required Iterable<SyncableTable> tables,
    required this.blobs,
    required this.deviceId,
    this.openBlobFile,
    this.checksumBlobFile,
    this.fetchBlob,
    this.clock = const Clock(),
  }) : stores = LenStores(tables);

  final LenStores stores;
  final BlobStore blobs;
  final String deviceId;

  /// Reads blob files in chunks where the platform has files.
  BlobFileOpener? openBlobFile;

  /// Checksums blob files off the UI thread where the platform can.
  BlobFileChecksum? checksumBlobFile;

  /// Downloads blobs not here yet, so exports hold them.
  BlobFetcher? fetchBlob;
  final Clock clock;

  /// Writes [scope] into [output] (see [LenArchiveWriter.write]).
  Future<LenWriteReport> write(
    LenScope scope,
    OutputStream output, {
    CancellationToken? cancel,
    void Function(double done)? onProgress,
    Future<void> Function()? drain,
  }) => LenArchiveWriter(
    stores,
    blobs,
    openBlobFile: openBlobFile,
    checksumBlobFile: checksumBlobFile,
    fetchBlob: fetchBlob,
    clock: clock,
  ).write(scope, output, cancel: cancel, onProgress: onProgress, drain: drain);

  /// The bytes of the files (PDFs, images, audio) a backup of the library
  /// holds, roughly: to warn before one too big for a browser.
  int libraryBlobBytes() {
    final referenced = BlobReferences(stores.any.database).all();
    return referenced.fold(0, (sum, sha) => sum + (blobs.sizeOf(sha) ?? 0));
  }

  /// Where Len files of a notebook or folder are imported: the folder
  /// open in the library (it sets this), whichever screen the import
  /// started from; null for the top level.
  String? Function() openFolder = () => null;

  /// Tells listeners that imported things changed (e.g. an import was
  /// undone), or that the library was backed up.
  void changed() => notifyListeners();

  /// Opens a Len file to import (see [LenSource.open]).
  Future<LenSource> open(InputStream input) => LenSource.open(input);

  LenArchiveReader get _reader => LenArchiveReader(stores, blobs, deviceId: deviceId, clock: clock);

  /// The notebooks of [source] here already (see [LenArchiveReader.present]).
  Map<String, String> present(LenSource source) => _reader.present(source);

  /// Imports [source] (see [LenArchiveReader.import]) and closes it.
  Future<LenImportResult> import(
    LenSource source, {
    String? parent,
    String? folderName,
    int folderColor = 0,
    bool keepIds = false,
    Set<String> skip = const {},
    CancellationToken? cancel,
    void Function(double done)? onProgress,
  }) async {
    final result = await _reader.import(
      source,
      parent: parent,
      folderName: folderName,
      folderColor: folderColor,
      keepIds: keepIds,
      skip: skip,
      cancel: cancel,
      onProgress: onProgress,
    );
    notifyListeners();
    return result;
  }
}
