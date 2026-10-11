import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/link_target.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/undo_history.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/messages.dart';
import '../editor_session.dart';
import '../tabs/open_notebooks.dart';
import 'link_pickers.dart';

/// A link element found on screen, with its target.
typedef LinkHit = ({SurfaceElement element, LinkTarget target});

/// Page and web links of one open notebook: finding them under a point,
/// following them, and making them from a lasso or PDF text selection.
class EditorLinks {
  EditorLinks(this.session, {Future<bool> Function(Uri url)? openUrl})
    : _openUrl = openUrl ?? _launch;

  final EditorSession session;
  final Future<bool> Function(Uri url) _openUrl;

  static Future<bool> _launch(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  /// The link under [screen] (topmost), if its content is loaded.
  LinkHit? linkAt(Offset screen) {
    final doc = session.doc;
    if (doc == null) {
      return _hit(session.canvas!, session.canvasViewport!.toWorld(screen));
    }
    final world = doc.viewport.toWorld(screen);
    final index = doc.layout.pageAt(world);
    if (index == null) return null;
    final model = doc.surfaces.peek(doc.pages[index].id)?.model;
    if (model == null) return null;
    return _hit(model, world - doc.layout.frameOf(index)!.topLeft);
  }

  static LinkHit? _hit(SurfaceModel model, Offset world) {
    final hits =
        model
            .elementsNear(Rect.fromCircle(center: world, radius: 1))
            .where((e) => LinkElements.isLink(e) && !model.isHidden(e.id) && e.contains(world))
            .toList()
          ..sort(SurfaceElement.paintOrder);
    for (final e in hits.reversed) {
      final target = LinkElements.targetOf(e);
      if (target != null) return (element: e, target: target);
    }
    return null;
  }

  /// Follows the link under [screen]; false if there is none.
  bool followAt(BuildContext context, Offset screen) {
    final hit = linkAt(screen);
    if (hit == null) return false;
    unawaited(follow(context, hit.target));
    return true;
  }

  /// A short description of [target] ("Page 3", "Page 2 of Physics",
  /// "example.com").
  String describe(LinkTarget target) => switch (target) {
    UrlLinkTarget(:final uri) =>
      uri.scheme == 'mailto' ? uri.path : uri.host + (uri.path == '/' ? '' : uri.path),
    PageLinkTarget(:final notebookId, :final pageId) => _describePage(notebookId, pageId),
  };

  String _describePage(String notebookId, String pageId) {
    final services = session.services;
    final pages = notebookId == session.notebook.id
        ? session.doc?.pages ?? const <NotebookPage>[]
        : services.pages.pagesOf(notebookId);
    final index = pages.indexWhere((p) => p.id == pageId);
    final page = index < 0 ? 'a deleted page' : 'page ${index + 1}';
    if (notebookId == session.notebook.id) return page.replaceFirst('p', 'P');
    final title = services.notebooks.get(notebookId)?.title;
    return title == null ? 'A deleted notebook' : '${page.replaceFirst('p', 'P')} of “$title”';
  }

  /// Goes where [target] leads: scrolls to a page of this notebook, opens
  /// another notebook at its page, or (after asking) opens a web address.
  Future<void> follow(BuildContext context, LinkTarget target) async {
    switch (target) {
      case UrlLinkTarget(:final uri):
        final open = await confirmAction(
          context,
          title: 'Open link?',
          message: uri.toString(),
          confirmLabel: 'Open',
          icon: Icons.open_in_new_rounded,
        );
        if (!open || !context.mounted) return;
        if (!await _openUrl(uri) && context.mounted) showMessage(context, 'Couldn’t open $uri');
      case PageLinkTarget(:final notebookId, :final pageId):
        _followPage(context, notebookId, pageId);
    }
  }

  void _followPage(BuildContext context, String notebookId, String pageId) {
    final services = session.services;
    final doc = session.doc;
    if (notebookId == session.notebook.id && doc != null) {
      final index = doc.pages.indexWhere((p) => p.id == pageId);
      if (index < 0) return showMessage(context, 'The linked page was deleted');
      doc.scrollToPage(index);
      return;
    }
    final Notebook? notebook = services.notebooks.get(notebookId);
    if (notebook == null || notebook.isTrashed) {
      return showMessage(context, 'The linked notebook was deleted');
    }
    final index = services.pages.pagesOf(notebookId).indexWhere((p) => p.id == pageId);
    if (index < 0) return showMessage(context, 'The linked page was deleted');
    final tabs = services.openNotebooks;
    // Opens at that page: a view that fits no screen size re-fits the page.
    tabs.saveView(
      notebookId,
      EditorViewState(
        scale: 1,
        offset: Offset.zero,
        page: index,
        size: Size.zero,
        fit: tabs.viewOf(notebookId)?.fit,
      ),
    );
    tabs.open(notebook);
  }

  // ---------------------------------------------------------------------------
  // Making links

  /// Asks where the lasso selection should lead and puts a link over it
  /// ([url]: a web address, else a page). Replaces links in the selection.
  Future<void> linkSelection(BuildContext context, {required bool url}) async {
    final selection = session.content.selection;
    final content = [...selection.elements.where((e) => !LinkElements.isLink(e))];
    if (selection.strokes.isEmpty && content.isEmpty) return;
    final existing = selection.elements.map(LinkElements.targetOf).nonNulls.firstOrNull;
    final target = url
        ? await pickUrlTarget(context, initial: existing is UrlLinkTarget ? existing : null)
        : await pickPageTarget(context, session);
    if (target == null || !context.mounted) return;
    final model = selection.model;
    final rect = SelectionController.boundsOf(selection.strokes, content);
    selection.replaceElements([
      ...content,
      LinkElements.create(
        id: session.services.elements.clock.newId(),
        surfaceId: model.surfaceId,
        rect: rect.inflate(LinkElements.padding),
        target: target,
        createdAt: session.services.elements.clock.nowMs(),
        z: model.bottomZ - 1,
      ),
    ]);
    showMessage(context, 'Linked to ${describe(target)}');
  }

  /// Removes the links in the lasso selection.
  void unlinkSelection() {
    final selection = session.content.selection;
    selection.replaceElements([...selection.elements.where((e) => !LinkElements.isLink(e))]);
  }

  /// Puts a link over [rects] (world rects of one line each) of [page],
  /// e.g. selected PDF text, as one undoable edit.
  Future<void> linkRegions(
    BuildContext context,
    NotebookPage page,
    List<Rect> rects, {
    required bool url,
  }) async {
    if (rects.isEmpty) return;
    final target = url ? await pickUrlTarget(context) : await pickPageTarget(context, session);
    if (target == null || !context.mounted) return;
    final model = session.doc!.surfaces.surfaceOf(page.id).model;
    final clock = session.services.elements.clock;
    final now = clock.nowMs();
    final z = model.bottomZ - 1;
    model.commit(
      InkEdit(
        addedElements: [
          for (final r in rects)
            LinkElements.create(
              id: clock.newId(),
              surfaceId: page.id,
              rect: r.inflate(LinkElements.padding / 2),
              target: target,
              createdAt: now,
              z: z,
            ),
        ],
      ),
    );
    showMessage(context, 'Linked to ${describe(target)}');
  }
}
