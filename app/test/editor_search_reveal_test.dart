import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/features/search/editor/editor_search_controller.dart';
import 'package:len/features/search/editor/editor_search_host.dart';
import 'package:len/features/search/editor/pdf_glyph_cache.dart';

import 'search_ui_test.dart' show seed;

/// A canvas host that counts its listeners and records what it reveals.
class _Host extends ChangeNotifier implements EditorSearchHost {
  bool ready = false;
  int listeners = 0;
  final List<String> revealed = [];

  @override
  Listenable get changes => this;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  @override
  bool get isReady => ready;

  @override
  NotebookPage? pageOf(String surfaceId) => null;

  @override
  SurfaceTransform? transformOf(String surfaceId) => null;

  @override
  void reveal(String surfaceId, Rect local, {EdgeInsets clear = EdgeInsets.zero}) =>
      revealed.add(surfaceId);

  @override
  void releaseRoom() {}

  void layOut() {
    ready = true;
    notifyListeners();
  }
}

void main() {
  late AppServices services;
  late String ideas;
  late _Host host;
  late EditorSearchController search;

  setUp(() {
    services = AppServices.create(AppDatabase.inMemory());
    ideas = seed(services).ideas.id;
    host = _Host();
    search = EditorSearchController(
      search: services.search,
      notebookId: ideas,
      host: host,
      glyphs: PdfGlyphCache(readBlob: (_) async => null),
    );
  });

  tearDown(() {
    search.dispose();
    services.dispose();
  });

  testWidgets('steps before the view is laid out wait with one listener', (tester) async {
    search.open(query: 'bulb');
    search
      ..next()
      ..next();
    await tester.pump();
    host.layOut();
    await tester.pump();
    expect(host.listeners, 0);
    expect(host.revealed, [ideas]);
  });

  testWidgets('text indexed while typing does not skip the scroll to the first match', (
    tester,
  ) async {
    host.ready = true;
    search.open();
    search.setQuery('bulb');
    await tester.pump(const Duration(milliseconds: 100));
    services.search.contentChanged(); // E.g. handwriting recognised meanwhile.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(search.matches, hasLength(1));
    expect(host.revealed, [ideas]);
  });
}
