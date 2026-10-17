import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../domain/recording.dart';
import '../../../ink/remote_ink.dart';
import '../../../ink/remote_pointers.dart';
import '../../../ink/surface_model.dart';
import '../../../sync/sync_engine.dart';
import '../../audio/notebook_audio.dart';
import '../../audio/recording_controller.dart';
import '../../documents/pdf/pdf_background_cache.dart';
import '../document/document_controller.dart';
import '../document/notebook_backgrounds.dart';
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
  SharedNotebook(
    this.services,
    Notebook notebook, {
    this._microphoneBusy,
    this._stoppedInBackground,
  }) : _notebook = notebook {
    _remote = services.sync.remoteChanges.listen(_onRemoteChanges);
    // In the notebook's room: other devices here show in presence, and
    // their strokes as they are written.
    services.sync.rooms.join(notebook.id);
    remoteInk = RemoteInk(services.sync.rooms, room: notebook.id)..shows = _shows;
    remotePointers = RemotePointers(services.sync.rooms, room: notebook.id);
  }

  /// The pointers (hovering pens and mice, lasers) of other devices in
  /// this notebook right now.
  late final RemotePointers remotePointers;

  /// The strokes other devices are writing in this notebook right now.
  late final RemoteInk remoteInk;

  final AppServices services;
  final String? Function()? _microphoneBusy;
  final void Function(Recording? saved, String? error)? _stoppedInBackground;
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
  NotebookAudio get audio => _audio ??= NotebookAudio(
    services,
    notebookId: id,
    microphoneBusy: _microphoneBusy,
    onStoppedInBackground: _stoppedInBackground,
  );
  NotebookAudio? _audio;

  /// The audio if it was asked for (else nothing to reload or save).
  NotebookAudio? get loadedAudio => _audio;

  /// Whether this notebook is recording (or about to, or saving).
  bool get recording => _audio != null && _audio!.recorder.state != RecorderState.idle;

  /// The infinite canvas's surface (made by [create] the first time).
  SurfaceModel canvasModel(SurfaceModel Function() create) => _canvas ??= create();
  SurfaceModel? _canvas;

  /// The pages' surfaces and the notebook-wide undo.
  PageModels get pages => _pages ??= PageModels();
  PageModels? _pages;

  /// Page backgrounds: rendered PDF pages ([pdfBackgrounds]) and scans.
  NotebookBackgrounds get backgrounds => _backgrounds ??= NotebookBackgrounds(
    pdf: PdfBackgroundCache(
      blobs: services.blobs,
      fetch: services.sync.fetchBlob,
      // Its text, links and outline were read as none while it was away
      // (freed, or not synced yet).
      onFetched: (_) => _pdfInfo?.retry(),
    ),
    images: services.images,
  );
  NotebookBackgrounds? _backgrounds;

  /// Rendered PDF page backgrounds.
  PdfBackgroundCache get pdfBackgrounds => backgrounds.pdf;

  /// Text, links and outlines of the PDF pages.
  PdfPageInfoCache get pdfInfo =>
      _pdfInfo ??= PdfPageInfoCache(PdfrxInfoSource(pdfBackgrounds.renderer, services.blobs));
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

  /// Reloads every view's page list (after a change none of them made).
  void reloadViews() => _reloadPages();

  /// Reloads surface [surfaceId] (a page or the canvas) after a change
  /// made beneath its views.
  void reloadSurface(String surfaceId) {
    if (surfaceId == _canvas?.surfaceId) _canvas!.reload();
    _pages?.reload(surfaceId);
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
        services.pages.addFreshPage(_notebook);
      }
      _reloadPages();
      _backgrounds?.pdf.retryMissing(); // New pages may bring new PDFs.
      _pdfInfo?.retry();
    }
    for (final surface in changes.strokeSurfaces) {
      final ids = changes.itemsOf(surface);
      if (ids == null) {
        reloadSurface(surface);
      } else {
        // Only what changed (a stroke written elsewhere a moment ago).
        if (surface == _canvas?.surfaceId) _canvas!.refreshItems(ids);
        _pages?.refresh(surface, ids);
      }
    }
    // Live ink whose stroke is drawn now goes (after: no frame without it);
    // on a surface reloading whole, once its load brought the stroke.
    remoteInk.landed(changes);
    _watchReloads();
  }

  /// The model of surface [id] (the canvas or a page), if one is open.
  SurfaceModel? _modelOf(String id) => id == _canvas?.surfaceId ? _canvas : _pages?.peek(id);

  /// Whether stroke [strokeId], whose record arrived, is drawn on [surface]
  /// (or cannot be: no view of it, or not in what its views load).
  bool _shows(String surface, String strokeId) {
    final model = _modelOf(surface);
    return model == null || model.strokeById(strokeId) != null || !model.isLoading;
  }

  /// Loads of the surfaces whose remote ink waits for them ([_shows]).
  final Map<String, StreamSubscription<SurfaceChange>> _reloads = {};

  /// Follows the loads of the surfaces reloading under remote ink: the ink
  /// goes in the frame their stroke arrives.
  void _watchReloads() {
    final waiting = remoteInk.reloading;
    for (final surface in waiting) {
      if (_reloads.containsKey(surface)) continue;
      final model = _modelOf(surface);
      if (model == null) continue;
      _reloads[surface] = model.changes.listen((change) {
        if (!change.loaded) return;
        remoteInk.recheck();
        if (!remoteInk.reloading.contains(surface)) unawaited(_reloads.remove(surface)?.cancel());
      });
    }
    for (final surface in [..._reloads.keys]) {
      if (!waiting.contains(surface)) unawaited(_reloads.remove(surface)!.cancel());
    }
  }

  /// Called by `SharedNotebooks` when the last editor let go: saves a
  /// running recording and releases everything.
  @override
  void dispose() {
    unawaited(_remote.cancel());
    for (final reload in _reloads.values) {
      unawaited(reload.cancel());
    }
    remoteInk.dispose();
    remotePointers.dispose();
    services.sync.rooms.leave(id);
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
