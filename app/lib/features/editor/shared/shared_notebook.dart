import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../ink/surface_model.dart';
import '../../../sync/sync_engine.dart';
import '../../audio/notebook_audio.dart';
import '../../audio/recording_controller.dart';
import '../../documents/pdf/pdf_background_cache.dart';
import '../document/document_controller.dart';
import '../document/page_models.dart';
import '../pdf/pdf_page_info.dart';
import '../pdf/pdf_page_info_cache.dart';

/// How an open notebook went away on another device.
enum NotebookGone { deleted, trashed }

/// A notebook open in one or more editors (a tab and the split view's
/// second pane, or both panes), and everything its editors share:
///
/// * the notebook itself — renamed or given new paper in one editor, every
///   editor shows it ([update], [notebook]; listen for changes);
/// * its audio: one recorder and player, one list of recordings;
/// * its PDF caches (rendered backgrounds, text and links);
/// * its surfaces with their undo history: the canvas's model, or the
///   pages' [PageModels], so two views draw into and undo the same models
///   and never need reloading after each other's edits;
/// * page list changes: when one view's pages change (added, deleted,
///   moved), the others reload theirs.
///
/// It follows remote changes once for all its editors; when the notebook
/// is deleted elsewhere, [gone] is set and listeners close their editors.
/// Get one from `SharedNotebooks`.
class SharedNotebook extends ChangeNotifier {
  SharedNotebook(this.services, Notebook notebook, {this._microphoneBusy}) : _notebook = notebook {
    _remote = services.sync.remoteChanges.listen(_onRemoteChanges);
  }

  final AppServices services;
  final String? Function()? _microphoneBusy;
  late final StreamSubscription<RemoteChanges> _remote;

  /// The notebook as currently known.
  Notebook get notebook => _notebook;
  Notebook _notebook;

  String get id => _notebook.id;

  /// Set once the notebook was deleted or trashed on another device.
  NotebookGone? get gone => _gone;
  NotebookGone? _gone;

  /// Changes the notebook (re-read first, so a concurrent remote change
  /// isn't overwritten wholesale); every editor of it updates.
  void update(Notebook Function(Notebook current) change) {
    final current = services.notebooks.get(id);
    if (current == null || _gone != null) return;
    _notebook = services.notebooks.update(change(current));
    services.openNotebooks.rename(id, _notebook.title);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Shared parts, made when first asked for

  /// Audio recording, playback and the recordings list.
  NotebookAudio get audio =>
      _audio ??= NotebookAudio(services, notebookId: id, microphoneBusy: _microphoneBusy);
  NotebookAudio? _audio;

  /// Whether this notebook is recording (or about to, or saving).
  bool get recording => _audio != null && _audio!.recorder.state != RecorderState.idle;

  /// The infinite canvas's surface (made by [create] the first time).
  SurfaceModel canvasModel(SurfaceModel Function() create) => _canvas ??= create();
  SurfaceModel? _canvas;

  /// The pages' surfaces and the notebook-wide undo.
  PageModels get pages => _pages ??= PageModels();
  PageModels? _pages;

  /// Rendered PDF page backgrounds.
  PdfBackgroundCache get backgrounds =>
      _backgrounds ??= PdfBackgroundCache(blobs: services.blobs, fetch: services.sync.fetchBlob);
  PdfBackgroundCache? _backgrounds;

  /// Text, links and outlines of the PDF pages.
  PdfPageInfoCache get pdfInfo =>
      _pdfInfo ??= PdfPageInfoCache(PdfrxInfoSource(backgrounds.renderer, services.blobs));
  PdfPageInfoCache? _pdfInfo;

  // ---------------------------------------------------------------------------
  // Page lists of the views

  /// Each view's document, how to reload its page list, and its listener.
  final Map<DocumentController, ({VoidCallback reload, VoidCallback listener})> _docs = {};
  bool _reloading = false;

  /// Keeps [doc] (a view of this notebook) current with page list changes
  /// made in other views and on other devices; [reload] reloads its pages.
  void attachDocument(DocumentController doc, VoidCallback reload) {
    var pages = doc.pages;
    void listener() {
      if (identical(doc.pages, pages)) return;
      pages = doc.pages;
      if (!_reloading) _reloadPages(except: doc); // Not a reload this caused.
    }

    _docs[doc] = (reload: reload, listener: listener);
    doc.addListener(listener);
  }

  void detachDocument(DocumentController doc) {
    final entry = _docs.remove(doc);
    if (entry != null) doc.removeListener(entry.listener);
  }

  void _reloadPages({DocumentController? except}) {
    _reloading = true;
    try {
      for (final doc in [..._docs.keys]) {
        if (doc != except) _docs[doc]?.reload();
      }
    } finally {
      _reloading = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Remote changes

  void _onRemoteChanges(RemoteChanges changes) {
    if (_gone != null) return;
    if (changes.notebooks) {
      final updated = services.notebooks.get(id);
      if (updated == null || updated.isTrashed) {
        _gone = updated == null ? NotebookGone.deleted : NotebookGone.trashed;
        notifyListeners();
        return;
      }
      _notebook = updated;
      services.openNotebooks.rename(id, updated.title);
      notifyListeners();
    }
    services.images.retryMissing(); // Image blobs may be on the server now.
    if (_docs.isNotEmpty && changes.pagesOfNotebooks.contains(id)) {
      // Every page deleted elsewhere: start a fresh one, as opening does.
      if (services.pages.pagesOf(id).isEmpty) {
        services.pages.addPage(id, paper: _notebook.paper);
      }
      _reloadPages();
      _backgrounds?.retryMissing(); // New pages may bring new PDFs.
      _pdfInfo?.retry();
    }
    for (final surfaceId in changes.strokeSurfaces) {
      if (surfaceId == _canvas?.surfaceId) _canvas!.reload();
      _pages?.reload(surfaceId);
    }
  }

  /// Called by `SharedNotebooks` when the last editor let go: saves a
  /// running recording and releases everything.
  @override
  void dispose() {
    unawaited(_remote.cancel());
    for (final doc in [..._docs.keys]) {
      detachDocument(doc);
    }
    _audio?.dispose(); // Saves a running recording.
    _canvas?.dispose();
    _pages?.dispose();
    _pdfInfo?.dispose();
    _backgrounds?.dispose();
    super.dispose();
  }
}
