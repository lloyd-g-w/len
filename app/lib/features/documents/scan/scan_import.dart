import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../../../app_services.dart';
import '../../../data/blob_references.dart';
import '../../../data/page_repository.dart';
import '../../../domain/cancellation.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../platform/scan_runner.dart';
import 'scan_session.dart';

/// Turns the pages of a scan into notebook pages whose backgrounds are
/// the flattened photos, each stored as a JPEG blob.
class ScanImporter {
  ScanImporter(this.services);

  final AppServices services;

  /// The blobs stored so far (dropped again by [discard]).
  final List<String> _stored = [];

  /// Flattens and stores [pages], cleaned up by [filter], one after the
  /// other; [onPage] hears each page about to start (and may throw to
  /// stop, e.g. [Cancelled]). Returns their page specs.
  Future<List<PageSpec>> render(
    List<ScanPageDraft> pages,
    ScanFilter filter, {
    void Function(int done, int total)? onPage,
  }) async {
    final specs = <PageSpec>[];
    for (final (i, page) in pages.indexed) {
      onPage?.call(i, pages.length);
      final job = await page.photo.job(page.quad, quarterTurns: page.turns, filter: filter);
      final out = await runScanJob(job);
      onPage?.call(i, pages.length); // Cancelled meanwhile: store nothing.
      final sha = await services.blobs.putBytes(out.jpeg, mime: 'image/jpeg');
      _stored.add(sha);
      specs.add((
        size: pageSizeFor(out.width, out.height),
        paper: Paper.blank,
        color: PaperColor.white,
        background: PageBackground.image(blob: sha),
      ));
    }
    return specs;
  }

  /// Creates a notebook titled [title] with [specs] as its pages.
  Notebook createNotebook(List<PageSpec> specs, {required String title, required int cover}) =>
      services.database.transaction(() {
        final notebook = services.notebooks.create(
          title: title,
          kind: NotebookKind.paged,
          paper: PaperStyle.blank,
          coverColor: cover,
        );
        final blank = services.pages.pagesOf(notebook.id);
        services.pages.insertPages(notebook.id, specs);
        for (final page in blank) {
          services.pages.delete(page.id);
        }
        return notebook;
      });

  /// Inserts [specs] into [notebookId] after [after] (at the end if null).
  List<NotebookPage> insertPages(
    List<PageSpec> specs, {
    required String notebookId,
    NotebookPage? after,
  }) => services.pages.insertPages(notebookId, specs, after: after);

  /// Deletes the blobs stored so far that nothing uses (the scan was
  /// cancelled or failed).
  Future<void> discard() async {
    final references = BlobReferences(services.database).all;
    for (final sha in _stored) {
      try {
        await services.blobs.discardIfUnreferenced(sha, references);
      } on Object catch (e) {
        debugPrint('Could not discard scan blob $sha: $e');
      }
    }
    _stored.clear();
  }

  /// The page size (world units, 96 per inch) of a scan of [width] ×
  /// [height] pixels: A4 or Letter (either way round) when its shape is
  /// within 3 % of theirs, else a page of A4's area with its shape (the
  /// camera can't tell how big the paper was).
  static Size pageSizeFor(int width, int height) {
    final aspect = width / height;
    for (final format in const [PageFormat.a4, PageFormat.letter]) {
      for (final size in [Size(format.width, format.height), Size(format.height, format.width)]) {
        if ((aspect / size.aspectRatio - 1).abs() <= 0.03) return size;
      }
    }
    final area = PageFormat.a4.width * PageFormat.a4.height;
    final h = math.sqrt(area / aspect);
    return Size((h * aspect).roundToDouble(), h.roundToDouble());
  }
}
