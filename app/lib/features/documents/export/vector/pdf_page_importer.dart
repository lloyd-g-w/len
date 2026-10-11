/// Copies pages of a source PDF into a `package:pdf` document as vectors.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart' as pw;
// ignore: implementation_imports
import 'package:pdf/src/priv.dart' as pw;

import 'cos.dart';
import 'imported_pdf_page.dart';
import 'pdf_filters.dart';
import 'pdf_source_reader.dart';

/// Imports pages of [PdfSourceReader]s into [target] as Form XObjects.
///
/// Objects shared between imported pages (fonts, images, …) are written once
/// per source for the importer's lifetime.
class PdfPageImporter {
  /// Creates an importer writing into [target].
  PdfPageImporter(this.target);

  /// The document receiving the copied objects.
  final pw.PdfDocument target;

  final _copied = <PdfSourceReader, Map<int, pw.PdfDataType>>{};
  final _forms = <PdfSourceReader, Map<int, pw.PdfImage>>{};

  static const _skippedTypes = {'Page', 'Pages', 'Catalog'};
  static const _skippedKeys = {'Parent', 'P'};

  /// Copies page [pageIndex] of [source]; throws [PdfReadException] if the
  /// page cannot be copied faithfully.
  ImportedPdfPage importPage(PdfSourceReader source, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= source.pageCount) {
      throw PdfReadException('No page $pageIndex');
    }
    final page = source.pages[pageIndex];
    final media = page.mediaBox ?? const [0.0, 0.0, 612.0, 792.0];
    final crop = _intersect(page.cropBox ?? media, media) ?? media;
    if (crop[2] - crop[0] <= 0 || crop[3] - crop[1] <= 0) {
      throw PdfReadException('Empty page box');
    }
    final values = <String, pw.PdfDataType>{
      '/BBox': pw.PdfArray.fromNum(crop),
      '/Resources': _convert(source, page.resources),
      if (page.dict['Group'] != null) '/Group': _convert(source, page.dict['Group']),
    };
    final Uint8List data;
    final contents = source.resolve(page.dict['Contents']);
    final single = contents is CosArray && contents.items.length == 1
        ? source.resolve(contents.items.first)
        : contents;
    if (single is CosStream) {
      if (single.dict['F'] != null) throw PdfReadException('External content stream');
      data = single.raw;
      for (final k in const ['Filter', 'DecodeParms']) {
        if (single.dict[k] != null) values['/$k'] = _convert(source, single.dict[k]);
      }
    } else if (single is CosArray) {
      final out = BytesBuilder(copy: false);
      for (final item in single.items) {
        final s = source.resolve(item);
        if (s == null) continue;
        if (s is! CosStream) throw PdfReadException('Bad content stream');
        if (out.isNotEmpty) out.addByte(0x0a);
        out.add(decodeStreamData(s, source.resolve));
      }
      data = out.toBytes();
    } else if (single == null) {
      data = Uint8List(0);
    } else {
      throw PdfReadException('Bad /Contents');
    }
    return ImportedPdfPage(
      content: rawFormXObject(target, values, data),
      annotations: _annotations(source, page),
      cropBox: crop,
      rotate: page.rotate,
    );
  }

  static List<double>? _intersect(List<double> a, List<double> b) {
    final r = [
      a[0] > b[0] ? a[0] : b[0],
      a[1] > b[1] ? a[1] : b[1],
      a[2] < b[2] ? a[2] : b[2],
      a[3] < b[3] ? a[3] : b[3],
    ];
    return r[2] > r[0] && r[3] > r[1] ? r : null;
  }

  List<AnnotationAppearance> _annotations(PdfSourceReader source, PdfSourcePage page) {
    final annots = source.resolve(page.dict['Annots']);
    if (annots is! CosArray) return const [];
    final result = <AnnotationAppearance>[];
    for (final item in annots.items) {
      final a = source.resolve(item);
      if (a is! CosDict || source.resolve(a['Subtype']).asName == 'Popup') continue;
      final flags = source.resolve(a['F']).asInt ?? 0;
      if (flags & 2 != 0 || flags & 32 != 0) continue; // Hidden, NoView
      final ap = source.resolve(a['AP']);
      if (ap is! CosDict) continue;
      var nRef = ap['N'];
      var n = source.resolve(nRef);
      if (n is CosDict) {
        final state = source.resolve(a['AS']).asName;
        if (state == null) continue;
        nRef = n[state];
        n = source.resolve(nRef);
      }
      if (n is! CosStream) continue;
      final rect = source.rectangle(a['Rect']);
      final bbox = source.rectangle(n.dict['BBox']);
      if (rect == null || bbox == null) continue;
      final mObj = source.resolve(n.dict['Matrix']);
      final m = mObj is CosArray && mObj.items.length == 6
          ? [for (final x in mObj.items) source.resolve(x).asNum?.toDouble() ?? 0.0]
          : const [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
      // Transform the bbox corners by /Matrix and take their bounding box.
      final xs = <double>[], ys = <double>[];
      for (final (x, y) in [
        (bbox[0], bbox[1]),
        (bbox[2], bbox[1]),
        (bbox[0], bbox[3]),
        (bbox[2], bbox[3]),
      ]) {
        xs.add(m[0] * x + m[2] * y + m[4]);
        ys.add(m[1] * x + m[3] * y + m[5]);
      }
      final bx0 = xs.reduce(_min), bx1 = xs.reduce(_max);
      final by0 = ys.reduce(_min), by1 = ys.reduce(_max);
      if (bx1 - bx0 <= 0 || by1 - by0 <= 0) continue;
      final kx = (rect[2] - rect[0]) / (bx1 - bx0), ky = (rect[3] - rect[1]) / (by1 - by0);
      final form = _form(source, nRef, n);
      result.add(
        AnnotationAppearance(form, [kx, 0, 0, ky, rect[0] - bx0 * kx, rect[1] - by0 * ky]),
      );
    }
    return result;
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;

  pw.PdfImage _form(PdfSourceReader source, CosObject? ref, CosStream stream) {
    final memo = _forms.putIfAbsent(source, () => {});
    final key = ref is CosRef ? ref.number : null;
    if (key != null && memo[key] != null) return memo[key]!;
    final form = rawFormXObject(
      target,
      _convertDict(source, stream.dict, stream: true).values,
      stream.raw,
    );
    if (key != null) memo[key] = form;
    return form;
  }

  pw.PdfDataType _convert(PdfSourceReader source, CosObject? o) => switch (o) {
    null || CosNull() => const pw.PdfNull(),
    CosBool(:final value) => pw.PdfBool(value),
    CosNumber(:final value) => pw.PdfNum(value),
    CosString(:final bytes, :final hex) => pw.PdfString(
      bytes,
      format: hex ? pw.PdfStringFormat.binary : pw.PdfStringFormat.literal,
    ),
    CosName(:final name) => pw.PdfName('/$name'),
    CosArray(:final items) => pw.PdfArray<pw.PdfDataType>([
      for (final i in items) _convert(source, i),
    ]),
    final CosDict d => _convertDict(source, d),
    final CosStream s => (_CopiedStream(target)..fill(this, source, s)).ref(),
    final CosRef r => _copyRef(source, r),
  };

  pw.PdfDict<pw.PdfDataType> _convertDict(
    PdfSourceReader source,
    CosDict d, {
    bool stream = false,
  }) => pw.PdfDict<pw.PdfDataType>.values({
    for (final e in d.entries.entries)
      if (!_skippedKeys.contains(e.key) && !(stream && e.key == 'Length'))
        '/${e.key}': _convert(source, e.value),
  });

  pw.PdfDataType _copyRef(PdfSourceReader source, CosRef ref) {
    final memo = _copied.putIfAbsent(source, () => {});
    final hit = memo[ref.number];
    if (hit != null) return hit;
    final o = source.getObject(ref.number);
    final typed = o is CosStream ? o.dict : o;
    if (o == null || (typed is CosDict && _skippedTypes.contains(typed['Type'].asName))) {
      return memo[ref.number] = const pw.PdfNull();
    }
    switch (o) {
      case CosStream():
        final t = _CopiedStream(target);
        memo[ref.number] = t.ref();
        t.fill(this, source, o);
      case CosDict():
        final t = pw.PdfObject<pw.PdfDict<pw.PdfDataType>>(target, params: pw.PdfDict.values({}));
        memo[ref.number] = t.ref();
        t.params.values.addAll(_convertDict(source, o).values);
      case CosArray():
        final t = pw.PdfObject<pw.PdfArray<pw.PdfDataType>>(target, params: pw.PdfArray());
        memo[ref.number] = t.ref();
        t.params.values.addAll([for (final i in o.items) _convert(source, i)]);
      default:
        memo[ref.number] = pw.PdfObject<pw.PdfDataType>(target, params: _convert(source, o)).ref();
    }
    return memo[ref.number]!;
  }
}

/// A stream object copied raw (filters preserved, `/Length` recomputed).
class _CopiedStream extends pw.PdfObject<pw.PdfDict<pw.PdfDataType>> {
  _CopiedStream(super.pdfDocument) : super(params: pw.PdfDict.values({}));

  Uint8List _data = Uint8List(0);

  void fill(PdfPageImporter importer, PdfSourceReader source, CosStream s) {
    if (s.dict['F'] != null) throw PdfReadException('External stream data (/F)');
    _data = s.raw;
    params.values.addAll(importer._convertDict(source, s.dict, stream: true).values);
  }

  @override
  void writeContent(pw.PdfStream s) {
    final values = Map.of(params.values)..remove('/Length');
    if (!values.containsKey('/Filter')) values.remove('/DecodeParms');
    pw.PdfDictStream(values: values, data: _data).output(this, s, settings.verbose ? 0 : null);
    s.putByte(0x0a);
  }
}
