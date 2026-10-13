import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/import/import_router.dart';
import 'package:len/features/documents/import/import_targets.dart';
import 'package:len/features/documents/import/incoming_files.dart';
import 'package:len/platform/incoming_args.dart';

XFile file(String name, {String? mime}) =>
    XFile.fromData(Uint8List(0), name: name, mimeType: mime, path: '/tmp/$name');

const paged = ImportDestination(title: 'Lecture', acceptsPdf: true);
const canvas = ImportDestination(title: 'Board', acceptsPdf: false);

class _Target implements ImportTarget {
  _Target(this.notebookId);

  @override
  final String notebookId;

  @override
  ImportDestination get destination => paged;

  @override
  Future<void> insertImages(List<XFile> files) async {}

  @override
  Future<void> insertPdf(XFile file) async {}
}

void main() {
  group('ImportRouter.kindOf', () {
    test('by extension, case-insensitive', () {
      expect(ImportRouter.kindOf(file('a.PDF')), IncomingKind.pdf);
      expect(ImportRouter.kindOf(file('a.jpeg')), IncomingKind.image);
      expect(ImportRouter.kindOf(file('a.HEIC')), IncomingKind.image);
      expect(ImportRouter.kindOf(file('a.docx')), IncomingKind.unsupported);
      expect(ImportRouter.kindOf(file('README')), IncomingKind.unsupported);
    });

    test('by MIME type when the name has no extension (Android content URIs)', () {
      expect(ImportRouter.kindOf(file('document', mime: 'application/pdf')), IncomingKind.pdf);
      expect(ImportRouter.kindOf(file('1000023', mime: 'image/png')), IncomingKind.image);
      expect(ImportRouter.kindOf(file('scan', mime: 'image/avif')), IncomingKind.image);
      expect(ImportRouter.kindOf(file('logo', mime: 'image/svg+xml')), IncomingKind.unsupported);
      expect(ImportRouter.kindOf(file('x', mime: 'text/plain')), IncomingKind.unsupported);
    });
  });

  group('ImportRouter.shouldAsk', () {
    test('only with an open editor that can take something', () {
      expect(ImportRouter.shouldAsk([file('a.pdf')], null), isFalse);
      expect(ImportRouter.shouldAsk([file('a.pdf')], paged), isTrue);
      expect(ImportRouter.shouldAsk([file('a.png')], canvas), isTrue);
      // A canvas has no pages: PDFs always become notebooks.
      expect(ImportRouter.shouldAsk([file('a.pdf')], canvas), isFalse);
      expect(ImportRouter.shouldAsk([file('a.txt')], paged), isFalse);
    });
  });

  group('ImportRouter.plan', () {
    test('nothing open: a notebook per PDF, one canvas for all images, last', () {
      final a = file('a.pdf'), b = file('b.pdf'), x = file('x.png'), y = file('y.jpg');
      final plan = ImportRouter.plan([x, a, y, b]);
      expect(plan.steps, hasLength(3));
      expect((plan.steps[0] as NewPdfNotebook).file, a);
      expect((plan.steps[1] as NewPdfNotebook).file, b);
      final images = plan.steps[2] as NewImageCanvas;
      expect(images.files, [x, y]);
      expect(images.title, 'Images');
      expect(plan.unsupported, isEmpty);
      expect(plan.unsupportedMessage, isNull);
    });

    test('inserting into a paged notebook: PDF pages and images go in', () {
      final a = file('a.pdf'), x = file('x.png');
      final plan = ImportRouter.plan([a, x], into: paged);
      expect(plan.steps, hasLength(2));
      expect((plan.steps[0] as InsertPdfPages).file, a);
      expect((plan.steps[1] as InsertImages).files, [x]);
    });

    test('inserting into a canvas: images go in, PDFs become notebooks afterwards', () {
      final a = file('a.pdf'), x = file('x.png');
      final plan = ImportRouter.plan([a, x], into: canvas);
      expect(plan.steps, hasLength(2));
      expect((plan.steps[0] as InsertImages).files, [x]);
      expect((plan.steps[1] as NewPdfNotebook).file, a);
    });

    test('unsupported files are reported in a friendly message', () {
      final one = ImportRouter.plan([file('notes.docx'), file('a.pdf')]);
      expect(one.steps, hasLength(1));
      expect(one.unsupported, ['notes.docx']);
      expect(
        one.unsupportedMessage,
        'Couldn’t open “notes.docx”: Len opens PDFs, images and Len files',
      );
      final many = ImportRouter.plan([file('a.zip'), file('b.mp3')]);
      expect(many.steps, isEmpty);
      expect(
        many.unsupportedMessage,
        'Couldn’t open 2 files: Len opens PDFs, images and Len files',
      );
    });

    test('a single image names its canvas', () {
      expect(ImportRouter.canvasTitleFor([file('IMG_2041.jpg')]), 'IMG 2041');
      expect(ImportRouter.canvasTitleFor([file('.png')]), '.png');
      expect(ImportRouter.canvasTitleFor([file('a.png'), file('b.png')]), 'Images');
    });
  });

  group('IncomingFiles', () {
    test('keeps batches until a handler is set (cold start), then delivers directly', () async {
      final incoming = IncomingFiles(Stream.value([file('a.pdf')]));
      addTearDown(incoming.dispose);
      await Future<void>.delayed(Duration.zero);
      final got = <List<String>>[];
      incoming.handler = (files) => got.add([for (final f in files) f.name]);
      expect(got, [
        ['a.pdf'],
      ]);
      incoming
        ..add([file('b.png'), file('c.png')])
        ..add([]); // Ignored.
      expect(got.last, ['b.png', 'c.png']);
      expect(got, hasLength(2));
      incoming
        ..handler = null
        ..add([file('d.pdf')]);
      expect(got, hasLength(2)); // Pending again.
    });
  });

  group('ImportTargets', () {
    test('the latest shown editor is active; waitFor completes when it registers', () async {
      final targets = ImportTargets();
      expect(targets.active, isNull);
      final a = _Target('a'), b = _Target('b');
      targets.add(a);
      final waiting = targets.waitFor('b');
      targets.add(b);
      expect(await waiting, b);
      expect(targets.active, b);
      targets.remove(b);
      expect(targets.active, a);
      expect(await targets.waitFor('a'), a);
      expect(await targets.waitFor('c', timeout: const Duration(milliseconds: 1)), isNull);
    });
  });

  group('incomingPathsFromArgs', () {
    test('paths and file URIs; options skipped', () {
      expect(
        incomingPathsFromArgs([
          '--verbose',
          'notes.pdf',
          '/home/me/My%20scan.png',
          'file:///home/me/My%20scan.png',
          'len://sync?url=https%3A%2F%2Fa&token=t',
          '',
        ], windows: false),
        ['notes.pdf', '/home/me/My%20scan.png', '/home/me/My scan.png'],
      );
      expect(incomingPathsFromArgs([r'C:\Users\me\a.pdf', 'file:///C:/x/b.pdf'], windows: true), [
        r'C:\Users\me\a.pdf',
        r'C:\x\b.pdf',
      ]);
    });

    test('len: links are links, not paths', () {
      expect(isIncomingLink('len://sync?url=x&token=y'), isTrue);
      expect(isIncomingLink('LEN://sync'), isTrue);
      expect(isIncomingLink('/home/me/len.pdf'), isFalse);
      expect(isIncomingLink('lens.pdf'), isFalse);
    });
  });
}
