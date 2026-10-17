import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_scope.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';

// Copies of pages and notebooks (duplicate, send to another notebook, Len
// files, version copies) keep their text flows: each copied box continues
// the copy of the box it continued, and one whose box before was not
// copied stands alone (its flow dropped) rather than continue a box
// elsewhere.

AppServices _services() {
  final s = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
  addTearDown(s.dispose);
  return s;
}

SurfaceElement _box(String id, String page, String text, {TextFlow? flow}) => SurfaceElement(
  id: id,
  surfaceId: page,
  type: ElementType.text.name,
  rect: const Rect.fromLTWH(40, 48, 300, 30),
  z: 1,
  createdAt: 1,
  data: TextData.rich(text: text).withFlow(flow).toJson(),
);

/// A notebook of three pages with a chain `h` → `c1` → `c2` across them;
/// with [stray], the third page also holds a box continuing `gone`, a box
/// that isn't there.
({Notebook notebook, List<String> pages}) _notebook(AppServices s, {bool stray = false}) {
  final n = s.notebooks.create(
    title: 'Flow',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0xFF3B5BDB,
  );
  final first = s.pages.pagesOf(n.id).single.id;
  final more = s.pages.insertPages(n.id, [
    for (var i = 0; i < 2; i++)
      (
        size: const Size(600, 800),
        paper: Paper(PaperStyle.blank),
        color: PaperColor.white,
        background: null,
      ),
  ]);
  final pages = [first, for (final p in more) p.id];
  s.elements.save([
    _box('h', pages[0], 'Alpha'),
    _box(
      'c1',
      pages[1],
      'beta',
      flow: const TextFlow(from: 'h', joined: true, numbers: [2]),
    ),
    _box('c2', pages[2], 'Gamma', flow: const TextFlow(from: 'c1')),
    if (stray) _box('s', pages[2], 'Stray', flow: const TextFlow(from: 'gone')),
  ]);
  return (notebook: n, pages: pages);
}

SurfaceElement _textOn(AppServices s, String page, String text) =>
    s.elements.allOn(page).singleWhere((e) => TextData.fromJson(e.data).text == text);

TextFlow? _flowOf(SurfaceElement e) => TextData.fromJson(e.data).flow;

/// Checks the chain copied onto [pages]; with [fresh], under new ids.
void _expectChain(AppServices s, List<String> pages, {bool fresh = true}) {
  final h = _textOn(s, pages[0], 'Alpha');
  final c1 = _textOn(s, pages[1], 'beta');
  final c2 = _textOn(s, pages[2], 'Gamma');
  if (fresh) {
    expect({h.id, c1.id, c2.id}.intersection({'h', 'c1', 'c2'}), isEmpty);
  }
  expect(_flowOf(h), isNull);
  expect(_flowOf(c1)!.from, h.id);
  expect(_flowOf(c1)!.joined, isTrue, reason: 'the rest of the flow is kept');
  expect(_flowOf(c1)!.numbers, [2]);
  expect(_flowOf(c2)!.from, c1.id);
}

void main() {
  test('a duplicated page: its continuation stands alone', () {
    final s = _services();
    final (:notebook, :pages) = _notebook(s);
    final copy = s.pages.insertPages(notebook.id, [
      (
        size: const Size(600, 800),
        paper: Paper(PaperStyle.blank),
        color: PaperColor.white,
        background: null,
      ),
    ]).single;
    SurfaceCopier(s.strokes, elements: s.elements).copy(from: pages[1], to: copy.id);
    expect(_flowOf(_textOn(s, copy.id, 'beta')), isNull);
    expect(_flowOf(_textOn(s, pages[1], 'beta'))!.from, 'h', reason: 'the original is kept');
  });

  test('a duplicated notebook', () {
    final s = _services();
    final (:notebook, pages: _) = _notebook(s);
    final copy = s.notebooks.duplicate(notebook.id)!;
    _expectChain(s, [for (final p in s.pages.pagesOf(copy.id)) p.id]);
  });

  test('pages sent to another notebook: all, or the last two', () {
    final s = _services();
    final (:notebook, :pages) = _notebook(s);
    Notebook other() => s.notebooks.create(
      title: 'Other',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    _expectChain(s, s.notebooks.copyPages(notebook.id, pages, other().id).pages);

    final two = s.notebooks.copyPages(notebook.id, pages.sublist(1), other().id).pages;
    final c1 = _textOn(s, two[0], 'beta');
    expect(_flowOf(c1), isNull, reason: 'its box before was not sent');
    expect(_flowOf(_textOn(s, two[1], 'Gamma'))!.from, c1.id);
  });

  test('a Len file imported (a copy) and restored (ids kept)', () async {
    final source = _services();
    final (:notebook, pages: _) = _notebook(source, stray: true);
    final out = OutputMemoryStream();
    await source.lenFiles.write(LenScope.notebook(notebook.id), out);
    final bytes = out.getBytes();

    for (final keepIds in [false, true]) {
      final target = _services();
      final imported = await target.lenFiles.import(
        await target.lenFiles.open(InputMemoryStream(bytes)),
        keepIds: keepIds,
      );
      final pages = [for (final p in target.pages.pagesOf(imported.notebooks.single)) p.id];
      _expectChain(target, pages, fresh: !keepIds);
      final stray = _textOn(target, pages[2], 'Stray');
      expect(_flowOf(stray), isNull, reason: 'a flow from a box not in the file is dropped');
      expect(target.elements.allOn(pages[2]), hasLength(2));
    }
  });

  test('a version copied as a new notebook', () async {
    final s = _services();
    final (:notebook, pages: _) = _notebook(s, stray: true);
    final version = (await s.versions.record(notebook.id))!;
    final copy = (await s.versions.copy(version, title: 'Copy'))!;
    final pages = [for (final p in s.pages.pagesOf(copy.id)) p.id];
    _expectChain(s, pages);
    expect(_flowOf(_textOn(s, pages[2], 'Stray')), isNull);
  });
}
