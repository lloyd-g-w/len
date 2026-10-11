/// A pure-Dart reader for (unencrypted) PDF files, used to copy pages.
library;

import 'dart:typed_data';

import 'cos.dart';
import 'pdf_filters.dart';
import 'pdf_lexer.dart';
import 'pdf_xref.dart';

/// A page of a [PdfSourceReader], with inherited attributes resolved.
class PdfSourcePage {
  /// Creates a page.
  PdfSourcePage({
    required this.dict,
    required this.ref,
    required this.resources,
    required this.mediaBox,
    required this.cropBox,
    required this.rotate,
  });

  /// The page dictionary itself (without inherited entries).
  final CosDict dict;

  /// The page's reference, when it is an indirect object.
  final CosRef? ref;

  /// The (inherited) `/Resources`, resolved; empty when absent.
  final CosDict resources;

  /// The (inherited) `/MediaBox` as normalised `[x0, y0, x1, y1]`, or null.
  final List<double>? mediaBox;

  /// The (inherited) `/CropBox` as normalised `[x0, y0, x1, y1]`, or null.
  final List<double>? cropBox;

  /// The (inherited) `/Rotate`, normalised to 0, 90, 180 or 270.
  final int rotate;
}

/// Parses a PDF and resolves its objects lazily.
///
/// Supports classic and stream cross-references, incremental updates, object
/// streams, and falls back to scanning the file when the cross-reference data
/// is broken. Encrypted files throw [PdfReadException].
class PdfSourceReader {
  PdfSourceReader._(this.bytes);

  /// Parses [bytes]; throws [PdfReadException] if the file is unsupported.
  static PdfSourceReader parse(Uint8List bytes) => PdfSourceReader._(bytes).._load();

  /// The file contents.
  final Uint8List bytes;

  /// The trailer dictionary (merged over incremental updates).
  CosDict get trailer => _trailer;

  /// The pages, in document order.
  List<PdfSourcePage> get pages => _pages;

  /// The number of pages.
  int get pageCount => _pages.length;

  /// Whether the cross-reference data was unusable and the file was scanned.
  bool get recoveredByScan => _scanned;

  Map<int, XrefEntry> _xref = {};
  CosDict _trailer = CosDict();
  List<PdfSourcePage> _pages = const [];
  bool _scanned = false;
  Map<int, XrefEntry>? _scanOffsets;
  final _cache = <int, CosObject?>{};
  final _objectStreams = <int, Map<int, CosObject>>{};
  final _resolving = <int>{};

  void _load() {
    try {
      final x = readXrefChain(bytes);
      _xref = x.entries;
      _trailer = x.trailer;
      _checkNotEncrypted(_trailer);
      _pages = _readPages();
      return;
    } on PdfReadException catch (e) {
      if (e is _EncryptedException) rethrow;
    }
    _recoverByScan();
    _pages = _readPages();
  }

  void _checkNotEncrypted(CosDict trailer) {
    final enc = trailer['Encrypt'];
    if (enc != null && enc is! CosNull) throw _EncryptedException();
  }

  void _recoverByScan() {
    _scanned = true;
    _cache.clear();
    _objectStreams.clear();
    final scan = scanObjects(bytes);
    _scanOffsets = scan.offsets;
    _xref = Map.of(scan.offsets);
    final trailers = [...scan.trailers];
    CosRef? catalog;
    for (final number in scan.offsets.keys.toList()..sort()) {
      final CosObject? o;
      try {
        o = getObject(number);
      } on PdfReadException {
        continue;
      }
      if (o is CosStream && o.dict['Type'].asName == 'XRef') trailers.add(o.dict);
      if (o is CosStream && o.dict['Type'].asName == 'ObjStm') {
        try {
          for (final n in _objectStream(number).keys) {
            _xref.putIfAbsent(n, () => XrefEntry.compressed(number, -1));
          }
        } on PdfReadException {
          // Unreadable object stream: its objects stay missing.
        }
      }
      final d = o is CosStream ? o.dict : o;
      if (d is CosDict && d['Type'].asName == 'Catalog') catalog = CosRef(number, 0);
    }
    trailers.forEach(_checkNotEncrypted);
    final withRoot = trailers.lastWhere(
      (t) => resolve(t['Root']) is CosDict,
      orElse: () => CosDict({'Root': ?catalog}),
    );
    if (withRoot['Root'] == null) throw PdfReadException('No document catalog found');
    _trailer = withRoot;
  }

  /// Resolves [object] if it is a reference (missing objects are null).
  CosObject? resolve(CosObject? object) => object is CosRef ? getObject(object.number) : object;

  /// The object with number [number], or null if it does not exist.
  CosObject? getObject(int number) {
    if (_cache.containsKey(number)) return _cache[number];
    if (!_resolving.add(number)) return null; // reference cycle (e.g. a /Length)
    try {
      final o = _load1(number);
      _cache[number] = o is CosNull ? null : o;
      return _cache[number];
    } finally {
      _resolving.remove(number);
    }
  }

  CosObject? _load1(int number) {
    final e = _xref[number];
    if (e == null || e.type == 0) return null;
    if (e.type == 2) {
      final objects = _objectStream(e.a);
      return objects[number];
    }
    final o = _parseAt(e.a, number);
    if (o != null) return o;
    final scanned = (_scanOffsets ??= scanObjects(bytes).offsets)[number];
    if (scanned != null && scanned.a != e.a) {
      final o2 = _parseAt(scanned.a, number);
      if (o2 != null) return o2;
    }
    throw PdfReadException('Object $number not found at its offset');
  }

  CosObject? _parseAt(int offset, int number) {
    if (offset < 0 || offset >= bytes.length) return null;
    try {
      final p = PdfParser(bytes, pos: offset, resolveLength: (r) => getObject(r.number).asInt);
      final o = p.parseIndirectObject();
      return o.number == number ? o.object : null;
    } on PdfReadException {
      return null;
    }
  }

  Map<int, CosObject> _objectStream(int number) {
    final cached = _objectStreams[number];
    if (cached != null) return cached;
    final s = getObject(number);
    if (s is! CosStream) throw PdfReadException('Object stream $number missing');
    final n = resolve(s.dict['N']).asInt ?? 0;
    final first = resolve(s.dict['First']).asInt ?? 0;
    final data = decodeStreamData(s, resolve);
    final header = PdfParser(data);
    final result = <int, CosObject>{};
    final pairs = <(int, int)>[];
    for (var i = 0; i < n; i++) {
      final objNum = header.tryReadInt(), off = header.tryReadInt();
      if (objNum == null || off == null) throw PdfReadException('Bad object stream header');
      pairs.add((objNum, off));
    }
    for (final (objNum, off) in pairs) {
      result.putIfAbsent(objNum, () => PdfParser(data, pos: first + off).parseObject());
    }
    return _objectStreams[number] = result;
  }

  List<PdfSourcePage> _readPages() {
    final root = resolve(_trailer['Root']);
    if (root is! CosDict) throw PdfReadException('Missing document catalog');
    final pages = <PdfSourcePage>[];
    final seen = <int>{};

    void walk(CosObject? node, Map<String, CosObject> inherited, int depth) {
      if (depth > 256) throw PdfReadException('Page tree too deep');
      if (node is CosRef && !seen.add(node.number)) return;
      final dict = resolve(node);
      if (dict is! CosDict) return;
      final inh = {
        ...inherited,
        for (final k in const ['Resources', 'MediaBox', 'CropBox', 'Rotate'])
          if (dict[k] != null) k: dict[k]!,
      };
      final kids = resolve(dict['Kids']);
      final type = dict['Type'].asName;
      if (type == 'Pages' || (type != 'Page' && kids is CosArray)) {
        if (kids is CosArray) {
          for (final kid in kids.items) {
            walk(kid, inh, depth + 1);
          }
        }
        return;
      }
      final res = resolve(inh['Resources']);
      final r = resolve(inh['Rotate']).asInt ?? 0;
      pages.add(
        PdfSourcePage(
          dict: dict,
          ref: node is CosRef ? node : null,
          resources: res is CosDict ? res : CosDict(),
          mediaBox: rectangle(inh['MediaBox']),
          cropBox: rectangle(inh['CropBox']),
          rotate: ((r ~/ 90) % 4 + 4) % 4 * 90,
        ),
      );
    }

    walk(root['Pages'], const {}, 0);
    return pages;
  }

  /// [object] resolved as a normalised rectangle `[x0, y0, x1, y1]`, or null.
  List<double>? rectangle(CosObject? object) {
    final a = resolve(object);
    if (a is! CosArray || a.items.length < 4) return null;
    final v = <double>[];
    for (final x in a.items.take(4)) {
      final n = resolve(x).asNum;
      if (n == null) return null;
      v.add(n.toDouble());
    }
    return [
      v[0] < v[2] ? v[0] : v[2],
      v[1] < v[3] ? v[1] : v[3],
      v[0] < v[2] ? v[2] : v[0],
      v[1] < v[3] ? v[3] : v[1],
    ];
  }
}

class _EncryptedException extends PdfReadException {
  _EncryptedException() : super('Encrypted PDF');
}
