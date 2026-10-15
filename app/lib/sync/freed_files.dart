import 'package:flutter/foundation.dart';

import '../data/blob_references.dart';
import '../data/blob_store.dart';
import 'sync_api.dart';

/// Files whose copies here Free up removed ([BlobStore.freed]) that the
/// sync server no longer has — one restored from an older backup: what to
/// tell the user, who can't otherwise know why they don't download.
class FreedFiles {
  FreedFiles(this.blobs, this.references);

  final BlobStore blobs;
  final BlobReferences references;

  /// When fetching blob [sha] found it missing on the server: the notice
  /// naming it and where it is, if it was freed here (else it may just not
  /// be uploaded yet: nothing to tell).
  String? missingNotice(String sha) {
    final mime = blobs.freed.mimeOf(sha);
    if (mime == null) return null;
    return '${_kind(mime)}${_where(references.notebookTitlesOf(sha))} can’t be downloaded: '
        'its copy here was removed with Free up, and the sync server no longer has it';
  }

  /// Asks the server for every freed file rows still show (after it
  /// changed or lost history) and returns the notice about those it lacks,
  /// or null if it has them all. Throws [SyncException] if it can't be
  /// asked.
  Future<String?> checkServer(SyncApi api) async {
    final live = references.all();
    final missing = <String>[];
    for (final sha in blobs.freed.all()) {
      if (live.contains(sha) && !await api.hasBlob(sha)) missing.add(sha);
    }
    if (missing.isEmpty) return null;
    debugPrint('The sync server lacks ${missing.length} freed files');
    final titles = {for (final sha in missing) ...references.notebookTitlesOf(sha)}.toList()
      ..sort();
    final one = missing.length == 1;
    return '${one ? '1 file' : '${missing.length} files'} removed here with Free up '
        '${one ? 'isn’t' : 'aren’t'} on the sync server any more${_inParens(titles)}: '
        'unless another device still has ${one ? 'it, it’s' : 'them, they’re'} lost';
  }

  static String _kind(String mime) => mime == 'application/pdf'
      ? 'A PDF'
      : mime.startsWith('image/')
      ? 'An image'
      : mime.startsWith('audio/')
      ? 'A recording'
      : 'A file';

  /// " in “A”", " in “A” and 2 other notebooks", or nothing.
  static String _where(List<String> titles) => switch (titles.length) {
    0 => '',
    1 => ' in “${titles.single}”',
    2 => ' in “${titles.first}” and 1 other notebook',
    _ => ' in “${titles.first}” and ${titles.length - 1} other notebooks',
  };

  static String _inParens(List<String> titles) =>
      titles.isEmpty ? '' : ' (${_where(titles).substring(1)})';
}
