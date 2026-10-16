import 'dart:ui';

import '../../../domain/notebook_page.dart';
import '../../../domain/surface_element.dart';
import '../../../domain/templates/pattern_builder.dart';
import '../../../ink/elements/text_flow_pages.dart';
import '../../../ink/surface_model.dart';
import 'document_commands.dart';
import 'document_controller.dart';
import 'document_layout.dart';

/// The pages of an open paged notebook for text boxes flowing across them
/// (see `TextFlowChains`): their margins (below a header area), where they
/// lie in continuous flow, their stored boxes and models, and pages added
/// at the end for text that runs on.
class DocumentTextFlow implements TextFlowPages {
  DocumentTextFlow({required this.doc, required this.commands});

  final DocumentController doc;
  final DocumentCommands commands;

  /// Pages added for text during the running [batch], recorded as one
  /// step with it once its edits are made.
  final List<NotebookPage> _added = [];

  int _index(String id) => doc.pages.indexWhere((p) => p.id == id);

  static FlowPage _flowPage(NotebookPage p) {
    final headed = p.paper.look.header && p.paper.style.hasHeader;
    return FlowPage.of(
      p.id,
      p.size,
      headerBottom: headed ? PatternBuilder.headerHeight(p.bounds) : 0,
    );
  }

  @override
  List<FlowPage>? pagesFrom(String pageId) {
    final i = _index(pageId);
    if (i == -1) return null;
    return [for (final p in doc.pages.skip(i)) _flowPage(p)];
  }

  @override
  String? pageBefore(String pageId) {
    final i = _index(pageId);
    return i > 0 ? doc.pages[i - 1].id : null;
  }

  @override
  Offset? offsetOf(String pageId, int k) {
    if (doc.flow != PageFlow.continuous) return null;
    final i = _index(pageId);
    final from = i == -1 ? null : doc.layout.frameOf(i);
    if (from == null) return null;
    final j = i + k;
    final last = doc.pages.length - 1;
    if (j <= last) return doc.layout.frameOf(j)?.topLeft.translate(-from.left, -from.top);
    // Pages to be added are like the last, one under another.
    final end = doc.layout.frameOf(last);
    if (end == null) return null;
    final top = end.top + (j - last) * (end.height + DocumentLayout.defaultGap);
    return Offset(end.left - from.left, top - from.top);
  }

  @override
  List<SurfaceElement> elementsOn(String pageId) =>
      doc.surfaces.elements?.allOn(pageId) ?? const [];

  @override
  SurfaceModel modelOf(String pageId) => doc.surfaces.surfaceOf(pageId).model;

  @override
  String addPage() {
    final last = doc.pages.last;
    final page = commands.actions.add(commands.actions.blankPageAfter(last), after: last);
    _added.add(page);
    commands.reload();
    return page.id;
  }

  /// Pages added are recorded last, so undoing the step deletes them with
  /// the text on them (kept for redo) before the boxes are taken back.
  @override
  void batch(void Function() edits) => doc.surfaces.models.group(() {
    try {
      edits();
    } finally {
      if (_added.isNotEmpty) {
        commands.edits.added([..._added], show: false);
        _added.clear();
      }
    }
  });

  @override
  void activate(String pageId) {
    final i = _index(pageId);
    if (i != -1) doc.activate(i);
  }
}
