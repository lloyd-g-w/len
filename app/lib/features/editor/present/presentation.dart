import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../ink/tool_settings.dart';
import '../../../platform/fullscreen.dart';
import '../chrome/focus_handle.dart';
import '../document/document_layout.dart';
import '../document/page_fit.dart';
import '../editor_session.dart';

/// Presentation mode of one editor: no chrome, full screen, the laser
/// pointer as the tool and, in paged notebooks, one whole page at a time.
/// [stop] puts back the tool and the page layout it found.
///
/// An external display mirrors the screen (Android's default); a separate
/// audience window would need multi-window support (see ARCHITECTURE).
class Presentation extends ChangeNotifier {
  Presentation(this.session);

  final EditorSession session;

  bool get active => _active;
  bool _active = false;

  EditorTool? _tool;
  PageFlow? _flow;
  PageFit? _fit;

  void start() {
    if (_active) return;
    _active = true;
    final tools = session.tools;
    _tool = tools.tool;
    tools.tool = EditorTool.laser;
    session.content.selection.clear();
    session.content.text.end();
    final doc = session.doc;
    if (doc != null) {
      _flow = doc.flow;
      _fit = doc.fit;
      doc.setFit(PageFit.page);
      doc.setFlow(PageFlow.single);
      doc.goToPage(doc.currentPage);
    }
    setImmersive(true);
    unawaited(setFullscreen(true));
    notifyListeners();
  }

  void stop() {
    if (!_active) return;
    _active = false;
    final tool = _tool;
    if (tool != null) session.tools.tool = tool;
    final doc = session.doc;
    if (doc != null) {
      if (_fit case final fit?) doc.setFit(fit);
      if (_flow case final flow?) doc.setFlow(flow);
      doc.goToPage(doc.currentPage);
    }
    setImmersive(false);
    unawaited(setFullscreen(false));
    notifyListeners();
  }

  void toggle() => _active ? stop() : start();

  /// The next or previous page ([delta] pages on).
  void turn(int delta) {
    final doc = session.doc;
    if (doc != null) doc.goToPage(doc.currentPage + delta);
  }
}
