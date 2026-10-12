import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../../domain/stroke.dart';
import '../input/stylus_batch.dart';
import 'input_recording.dart';

/// Reads and writes `.leninput` files: UTF-8 JSON, versioned.
///
/// ```text
/// { "format": "leninput", "version": 1, "meta": {…},
///   "entries": [
///     ["p", t, type, kind, pointer, device, timeStampUs, x, y, localX, localY,
///      pressure, pressureMin, pressureMax, buttons, synthesized(0/1), tilt, orientation],
///     ["b", t, [[device, downTimeUs, eventTimeUs, [[timeUs, x, y, pressure, tilt, orientation], …]], …]],
///     ["f", t, vsyncUs],
///     ["ft", t, frameNumber, vsyncStartUs, buildUs, rasterUs, totalUs] ] }
/// ```
/// `t` is µs since the recording started; positions are logical px except
/// batch samples (physical px of the Flutter view, as on the channel).
/// Unknown entry tags and meta fields are ignored (forward compatible).
abstract final class RecordingCodec {
  static const String format = 'leninput';
  static const int version = 1;
  static const String extension = 'leninput';
  static const String mime = 'application/json';

  static Uint8List encode(InputRecording r) =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson(r))));

  /// Parses a file; throws [FormatException] when it is not a recording.
  static InputRecording decode(List<int> bytes) => fromJson(jsonDecode(utf8.decode(bytes)));

  static Map<String, Object?> toJson(InputRecording r) => {
    'format': format,
    'version': version,
    'meta': _metaToJson(r.meta),
    'entries': [for (final e in r.entries) _entryToJson(e)],
  };

  static InputRecording fromJson(Object? json) {
    if (json is! Map || json['format'] != format) {
      throw const FormatException('not a .leninput recording');
    }
    final v = json['version'];
    if (v is! int || v > version) throw FormatException('unsupported version $v');
    final entries = <InputEntry>[];
    for (final e in (json['entries'] as List? ?? const [])) {
      final entry = _entryFromJson(e as List<Object?>);
      if (entry != null) entries.add(entry);
    }
    return InputRecording(
      meta: _metaFromJson(json['meta'] as Map<Object?, Object?>),
      entries: entries,
    );
  }

  // ---------------------------------------------------------------------------

  static Map<String, Object?> _metaToJson(RecordingMeta m) => {
    'createdAt': m.createdAtMs,
    'platform': m.platform,
    'note': m.note,
    'dpr': m.devicePixelRatio,
    'size': [m.viewSize.width, m.viewSize.height],
    'scale': m.viewScale,
    'offset': [m.viewOffset.dx, m.viewOffset.dy],
    'stylusOnly': m.stylusOnly,
    'pen': {
      'tool': m.pen.tool.name,
      'color': m.pen.color,
      'width': m.pen.width,
      'opacity': m.pen.opacity,
      'thinning': m.pen.thinning,
      'streamline': m.pen.streamline,
      'taper': m.pen.taper,
    },
  };

  static RecordingMeta _metaFromJson(Map<Object?, Object?> m) {
    final pen = m['pen'] as Map<Object?, Object?>? ?? const {};
    final size = m['size'] as List? ?? const [800, 600];
    final offset = m['offset'] as List? ?? const [0, 0];
    return RecordingMeta(
      createdAtMs: _int(m['createdAt']),
      platform: m['platform'] as String? ?? 'unknown',
      note: m['note'] as String? ?? '',
      devicePixelRatio: _num(m['dpr'], 1),
      viewSize: Size(_num(size[0]), _num(size[1])),
      viewScale: _num(m['scale'], 1),
      viewOffset: Offset(_num(offset[0]), _num(offset[1])),
      stylusOnly: m['stylusOnly'] != false,
      pen: PenSettings(
        tool: InkTool.values.firstWhere(
          (t) => t.name == pen['tool'],
          orElse: () => InkTool.ballpoint,
        ),
        color: _int(pen['color'], 0xFF000000),
        width: _num(pen['width'], 2.5),
        opacity: _num(pen['opacity'], 1),
        thinning: _num(pen['thinning'], 0.25),
        streamline: _num(pen['streamline'], 0.4),
        taper: pen['taper'] == true,
      ),
    );
  }

  static List<Object?> _entryToJson(InputEntry e) => switch (e) {
    PointerEntry() => [
      'p',
      e.t,
      e.type.index,
      e.kind.index,
      e.pointer,
      e.device,
      e.timeStampUs,
      _r(e.position.dx),
      _r(e.position.dy),
      _r(e.localPosition.dx),
      _r(e.localPosition.dy),
      _r(e.pressure, 1e5),
      e.pressureMin,
      e.pressureMax,
      e.buttons,
      e.synthesized ? 1 : 0,
      _r(e.tilt, 1e4),
      _r(e.orientation, 1e4),
    ],
    BatchEntry() => ['b', e.t, for (final b in e.batches) _batchToJson(b)],
    FrameEntry() => ['f', e.t, e.vsyncUs],
    TimingEntry() => ['ft', e.t, e.frameNumber, e.vsyncStartUs, e.buildUs, e.rasterUs, e.totalUs],
  };

  static List<Object?> _batchToJson(StylusBatch b) => [
    b.device,
    b.downTimeUs,
    b.eventTimeUs,
    [
      for (final s in b.samples)
        [s.timeUs, _r(s.x), _r(s.y), _r(s.pressure, 1e5), _r(s.tilt, 1e4), _r(s.orientation, 1e4)],
    ],
  ];

  static InputEntry? _entryFromJson(List<Object?> e) {
    final t = _int(e[1]);
    switch (e[0]) {
      case 'p':
        return PointerEntry(
          t,
          type: PointerType.values[_int(e[2])],
          kind: PointerDeviceKind.values[_int(e[3])],
          pointer: _int(e[4]),
          device: _int(e[5]),
          timeStampUs: _int(e[6]),
          position: Offset(_num(e[7]), _num(e[8])),
          localPosition: Offset(_num(e[9]), _num(e[10])),
          pressure: _num(e[11]),
          pressureMin: _num(e[12]),
          pressureMax: _num(e[13], 1),
          buttons: _int(e[14]),
          synthesized: e[15] == 1,
          tilt: e.length > 16 ? _num(e[16]) : 0,
          orientation: e.length > 17 ? _num(e[17]) : 0,
        );
      case 'b':
        return BatchEntry(t, [for (final b in e.skip(2)) _batchFromJson(b as List<Object?>)]);
      case 'f':
        return FrameEntry(t, vsyncUs: _int(e[2]));
      case 'ft':
        return TimingEntry(
          t,
          frameNumber: _int(e[2]),
          vsyncStartUs: _int(e[3]),
          buildUs: _int(e[4]),
          rasterUs: _int(e[5]),
          totalUs: _int(e[6]),
        );
    }
    return null;
  }

  static StylusBatch _batchFromJson(List<Object?> b) => StylusBatch(
    device: _int(b[0]),
    downTimeUs: _num(b[1]),
    eventTimeUs: _num(b[2]),
    samples: [
      for (final s in (b[3] as List<Object?>).cast<List<Object?>>())
        StylusSample(
          timeUs: _num(s[0]),
          x: _num(s[1]),
          y: _num(s[2]),
          pressure: _num(s[3]),
          tilt: _num(s[4]),
          orientation: _num(s[5]),
        ),
    ],
  );

  /// Rounds to 1/[scale] to keep files small (float32 sources anyway).
  static double _r(double v, [double scale = 1e3]) => (v * scale).roundToDouble() / scale;
  static double _num(Object? v, [double orElse = 0]) => v is num ? v.toDouble() : orElse;
  static int _int(Object? v, [int orElse = 0]) => v is num ? v.round() : orElse;
}
