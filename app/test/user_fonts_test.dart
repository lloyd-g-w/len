import 'dart:convert';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_scope.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/blob_references.dart';
import 'package:len/data/font_repository.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/font_file.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/domain/text/text_record.dart';
import 'package:len/ink/fonts/text_fonts.dart';
import 'package:len/ink/fonts/user_font_library.dart';

import 'support/font_fixtures.dart';
import 'support/two_devices.dart';

AppServices _services() =>
    AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());

FontRepository _repo(AppServices s) => s.sync.engine.repositories.fonts;

/// A notebook whose page holds a text box in [font].
Notebook _notebookWith(AppServices s, TextFont font, {String title = 'Notes'}) {
  final n = s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );
  final page = s.pages.pagesOf(n.id).single;
  s.elements.save([
    SurfaceElement(
      id: 'box-$title',
      surfaceId: page.id,
      type: ElementType.text.name,
      rect: const Rect.fromLTWH(10, 10, 200, 40),
      rotation: 0,
      z: 1,
      createdAt: 1,
      data: TextData(text: 'Hello', font: font).toJson(),
    ),
  ]);
  return n;
}

Future<Uint8List> _export(AppServices s, LenScope scope) async {
  final out = OutputMemoryStream();
  await s.lenFiles.write(scope, out);
  return out.getBytes();
}

Future<void> _import(AppServices s, Uint8List bytes) async =>
    s.lenFiles.import(await s.lenFiles.open(InputMemoryStream(bytes)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(TextFonts.reset);

  group('font files', () {
    test('a TrueType file gives its family, style and outlines', () {
      final info = FontFileInfo.read(caveatFile())!;
      expect(info.family, 'Caveat');
      expect(info.displayName, 'Caveat');
      expect(info.outlines, FontOutlines.trueType);
    });

    test('an OpenType (CFF) file is read; its typographic family wins', () {
      final info = FontFileInfo.read(
        sfnt(
          0x4F54544F,
          const ['cmap', 'head', 'hhea', 'hmtx', 'maxp', 'CFF '],
          {1: 'Source Serif 4 Semibold', 2: 'Regular', 16: 'Source Serif 4', 17: 'Semibold Italic'},
        ),
      )!;
      expect(info.outlines, FontOutlines.cff);
      expect(info.displayName, 'Source Serif 4 Semibold Italic');
    });

    test('other files are refused', () {
      const tables = ['cmap', 'head', 'hhea', 'hmtx', 'maxp', 'glyf'];
      expect(FontFileInfo.read(Uint8List.fromList(utf8.encode('not a font at all'))), isNull);
      expect(FontFileInfo.read(sfnt(0x74746366 /* ttcf */, tables, {1: 'A'})), isNull);
      expect(FontFileInfo.read(sfnt(0x774F4646 /* wOFF */, tables, {1: 'A'})), isNull);
      // No outlines, no name.
      expect(FontFileInfo.read(sfnt(0x00010000, tables.sublist(0, 5), {1: 'A'})), isNull);
      expect(FontFileInfo.read(sfnt(0x00010000, tables, {2: 'Bold'})), isNull);
      // Cut short.
      expect(FontFileInfo.read(caveatFile().sublist(0, 40)), isNull);
    });
  });

  group('text data', () {
    test('a box or span may name a user font by id; other names are malformed', () {
      final font = TextFont.user('0123456789abcdef0123456789abcdef');
      final data = TextData.rich(
        text: 'Hi there',
        spans: [StyledRange(0, 2, SpanStyle(font: font))],
        paras: const [],
        font: font,
      );
      final parsed = TextRecord.parse(data.toJson());
      expect(parsed.font, font);
      expect(parsed.spans.single.style.font, font);
      expect(() => TextRecord.parse({...data.toJson(), 'font': 'comic'}), throwsFormatException);
      expect(
        () => TextRecord.parse({...data.toJson(), 'font': '0123456789ABCDEF0123456789ABCDEF'}),
        throwsFormatException,
      );
      // The tolerant reader falls back.
      expect(TextData.fromJson({...data.toJson(), 'font': 'comic'}).font, TextFont.inter);
    });
  });

  group('library', () {
    test('importing stores the file once, named from it; the id is the file\'s', () async {
      final s = _services();
      addTearDown(s.dispose);
      final font = await s.fonts.import(caveatFile());
      expect(font.name, 'Caveat');
      expect(font.id, TextFont.userIdOf(font.blob));
      expect(s.blobs.mimeOf(font.blob), 'font/ttf');
      expect(await s.fonts.import(caveatFile()), font);
      expect(s.fonts.fonts, [font]);
      expect(TextFonts.isShown(font.font), isTrue);
      expect(TextFonts.familyOf(font.font), font.font.family);
      await expectLater(s.fonts.import(Uint8List(100)), throwsFormatException);
    });

    test('a removed font falls back to the default; restoring brings it back', () async {
      final s = _services();
      addTearDown(s.dispose);
      final font = await s.fonts.import(caveatFile());
      await s.fonts.remove(font);
      expect(s.fonts.fonts, isEmpty);
      expect(TextFonts.isShown(font.font), isFalse);
      expect(TextFonts.familyOf(font.font), TextFont.inter.family);
      expect(TextFonts.labelOf(font.font), 'Missing font');
      await s.fonts.restore(font);
      expect(TextFonts.isShown(font.font), isTrue);
    });

    test('blob references keep a font\'s file until it is removed', () async {
      final s = _services();
      addTearDown(s.dispose);
      final font = await s.fonts.import(caveatFile());
      final refs = BlobReferences(s.database);
      expect(refs.all(), contains(font.blob));
      expect(refs.keeps(font.blob, 0), isTrue);
      // Text naming the font does not keep its file (it falls back).
      _notebookWith(s, font.font);
      await s.fonts.remove(font);
      expect(refs.all(), isNot(contains(font.blob)));
      expect(refs.keeps(font.blob, 0), isFalse);
    });
    test('fonts are listed in natural order: "Font 2" before "Font 10", any case', () {
      final s = _services();
      addTearDown(s.dispose);
      for (final name in ['Font 10', 'font 2', 'Source Serif 4', 'Font 1', 'caveat']) {
        _repo(s).add(name: name, blob: sha256.convert(utf8.encode(name)).toString());
      }
      expect(_repo(s).list().map((f) => f.name), [
        'caveat',
        'Font 1',
        'font 2',
        'Font 10',
        'Source Serif 4',
      ]);
    });
  });

  group('sync', () {
    test('a font reaches the other device with its file, and its removal too', () async {
      final (a, b) = twoDevices();
      final font = await a.s.fonts.import(caveatFile());
      await send(a, b);
      expect(a.server.blobs[font.blob], caveatFile());
      expect(_repo(b.s).list(), [font]);

      // B loads it once it fetched the file.
      final library = UserFontLibrary(
        repository: _repo(b.s),
        blobs: b.s.blobs,
        fetch: (sha) async {
          await b.s.blobs.putBytes(Uint8List.fromList(a.server.blobs[sha]!), mime: 'font/ttf');
          return true;
        },
      );
      addTearDown(library.dispose);
      await library.refresh();
      expect(TextFonts.isShown(font.font), isTrue);

      await a.s.fonts.remove(font);
      await send(a, b);
      expect(_repo(b.s).list(), isEmpty);
      await library.refresh();
      expect(TextFonts.isShown(font.font), isFalse);
    });

    test('a font whose file couldn\'t be had is tried again after a sync that worked', () async {
      final s = _services();
      addTearDown(s.dispose);
      // Another file than the other tests' (they load theirs for good).
      final bytes = Uint8List.fromList([...caveatFile(), 0, 0, 0, 0]);
      final sha = sha256.convert(bytes).toString();
      final font = _repo(s).add(name: 'Later', blob: sha);
      var online = false;
      var lastSync = 0;
      final status = ChangeNotifier();
      addTearDown(status.dispose);
      final library = UserFontLibrary(
        repository: _repo(s),
        blobs: s.blobs,
        fetch: (_) async {
          if (!online) return false;
          await s.blobs.putBytes(bytes, mime: 'font/ttf');
          return true;
        },
        syncStatus: status,
        syncMark: () => lastSync,
      );
      addTearDown(library.dispose);
      await library.refresh();
      expect(TextFonts.isShown(font.font), isFalse);

      online = true;
      // A sync state change that is no new success: nothing tried.
      status.notifyListeners();
      await pumpEventQueue();
      expect(await s.blobs.read(sha), isNull);
      lastSync = 1;
      status.notifyListeners();
      for (var i = 0; i < 100 && !TextFonts.isShown(font.font); i++) {
        await pumpEventQueue();
      }
      expect(TextFonts.isShown(font.font), isTrue);
    });

    test('the same file imported on two devices is one font', () async {
      final (a, b) = twoDevices();
      final fa = await a.s.fonts.import(caveatFile());
      final fb = await b.s.fonts.import(caveatFile());
      await send(a, b);
      await send(b, a);
      expect(fa.id, fb.id);
      expect(_repo(a.s).list().map((f) => f.id), [fa.id]);
      expect(_repo(b.s).list().map((f) => f.id), [fa.id]);
    });

    test('a font record is parsed strictly', () {
      SyncRecord record(String id, Map<String, Object?> data) => SyncRecord(
        collection: 'fonts',
        id: id,
        updatedAt: 1,
        deviceId: 'd',
        deleted: false,
        data: data,
      );
      final blob = 'ab' * 32;
      final id = TextFont.userIdOf(blob);
      expect(
        FontRepository.parse(record(id, {'name': 'X', 'blob': blob, 'createdAt': 1})).name,
        'X',
      );
      for (final (rid, data) in [
        ('other', {'name': 'X', 'blob': blob, 'createdAt': 1}),
        (id, {'name': ' ', 'blob': blob, 'createdAt': 1}),
        (id, {'name': 'X', 'blob': 'nope', 'createdAt': 1}),
        (id, {'name': 'X', 'blob': blob}),
      ]) {
        expect(() => FontRepository.parse(record(rid, data)), throwsFormatException);
      }
    });
  });

  group('Len files', () {
    test('a notebook carries the fonts its text uses; importing adds them once', () async {
      final source = _services(), target = _services();
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      final used = await source.fonts.import(caveatFile());
      final n = _notebookWith(source, used.font);
      final bytes = await _export(source, LenScope.notebook(n.id));
      final names = [for (final f in ZipDecoder().decodeBytes(bytes)) f.name];
      expect(names, contains('blobs/${used.blob}'));

      final library = target.fonts; // (As the app's, listening.)
      await _import(target, bytes);
      // Shown at once, without a restart.
      expect(library.fonts.map((f) => f.id), [used.id]);
      final imported = _repo(target).list().single;
      expect(imported.id, used.id);
      expect(imported.name, 'Caveat');
      expect(await target.blobs.read(used.blob), caveatFile());
      expect(_repo(target).dirtyRecords(10).map((r) => r.id), [used.id]);
      final box = target.elements.db.select("SELECT data FROM elements WHERE type = 'text'");
      expect((jsonDecode(box.single['data'] as String) as Map)['font'], used.id);

      // Again: still one font.
      await _import(target, bytes);
      expect(_repo(target).list(), hasLength(1));
    });

    test(
      'a notebook without user fonts carries none; a backup carries all, removed ones come back',
      () async {
        final source = _services(), target = _services();
        addTearDown(source.dispose);
        addTearDown(target.dispose);
        final font = await source.fonts.import(caveatFile());
        final plain = _notebookWith(source, TextFont.lora, title: 'Plain');
        await _import(target, await _export(source, LenScope.notebook(plain.id)));
        expect(_repo(target).list(), isEmpty);

        // Removed here, then a backup restored.
        await target.fonts.import(caveatFile());
        await target.fonts.remove(target.fonts.fonts.single);
        await _import(target, await _export(source, const LenScope.library()));
        expect(_repo(target).list().single.id, font.id);
        final record = _repo(target).dirtyRecords(10).single;
        expect(record.deleted, isFalse);
      },
    );
  });
}
