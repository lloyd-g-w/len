import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/stroke_row.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/sync/pull_page.dart';

/// A live stroke record's payload with [points] (x, y, pressure).
Map<String, Object?> _data(List<(double, double, double)> points, {double width = 2}) => {
  'surfaceId': 'page',
  'tool': 'ballpoint',
  'color': 0xFF000000,
  'width': width,
  'points': base64Encode(
    _raw([
      for (final (x, y, p) in points) ...[x, y, p],
    ]),
  ),
  'createdAt': 7,
  'style': StrokeStyle.defaultsFor(InkTool.ballpoint).toJson(),
};

/// Float32 values as stored, unchecked (pressures may be out of range).
Uint8List _raw(List<double> values) {
  final data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List _page(List<Map<String, Object?>> records) =>
    utf8.encode(jsonEncode({'records': records, 'nextSince': records.length, 'hasMore': false}));

Map<String, Object?> _record(String id, Map<String, Object?>? data) => {
  'collection': 'strokes',
  'id': id,
  'updatedAt': 1,
  'deviceId': 'd',
  'deleted': data == null,
  'data': data,
};

void main() {
  group('StrokeRow.fromRecord', () {
    // The fast path (points as they are, one chunk) must store exactly
    // what building the stroke stores.
    final cases = {
      'one chunk': _data([(10, 10, 0.5), (40, 12, 1), (60, 30, 0)]),
      'one point': _data([(100, 100, 0.3)]),
      'across chunks': _data([(10, 10, 0.5), (900, 1400, 0.5)]),
      'pressure out of range': _data([(10, 10, 1.5), (20, 10, -0.2)]),
      'another style': {
        ..._data([(10, 10, 0.5), (12, 14, 0.6)]),
        'style': StrokeStyle.defaultsFor(InkTool.highlighter).toJson(),
      },
    };
    for (final MapEntry(key: name, value: data) in cases.entries) {
      test(name, () {
        final fast = StrokeRow.fromRecord('s', data);
        final slow = StrokeRow.of(StrokeRow.strokeFromRecord('s', data));
        expect(fast.points, slow.points);
        expect(fast.chunks.toSet(), slow.chunks.toSet());
        expect(
          [fast.surfaceId, fast.tool, fast.color, fast.width, fast.createdAt, fast.style],
          [slow.surfaceId, slow.tool, slow.color, slow.width, slow.createdAt, slow.style],
        );
      });
    }

    test('rejects what the stroke would reject', () {
      for (final data in [
        _data([]),
        _data([(double.nan, 0, 0.5)]),
        _data([(0, 0, 0.5)], width: 0),
        _data([(0, 0, 0.5)], width: 5000),
        _data([(1e12, 0, 0.5)]),
        {
          ..._data([(0, 0, 0.5)]),
          'tool': 'quill',
        },
        {
          ..._data([(0, 0, 0.5)]),
          'points': 'AAAA',
        },
      ]) {
        expect(() => StrokeRow.fromRecord('s', data), throwsA(anything), reason: '$data');
      }
    });
  });

  group('decodePullPage', () {
    test('prepares live strokes; leaves tombstones and bad strokes', () {
      final page = decodePullPage(
        _page([
          _record('good', _data([(1, 1, 0.5)])),
          _record('gone', null),
          _record('bad', {
            ..._data([(1, 1, 0.5)]),
            'width': -1,
          }),
          {'collection': 'strokes'},
        ]),
        since: 0,
      )!;
      expect(page.malformed, 1);
      final [good, gone, bad] = page.records;
      expect(good.prepared, isA<StrokeRow>());
      expect(good.data, {'surfaceId': 'page'});
      expect(gone.prepared, isNull);
      expect(bad.prepared, isNull);
      expect(bad.data!['width'], -1, reason: 'the store reports it');
    });

    test('a body that is not a page is null', () {
      expect(decodePullPage(utf8.encode('{"records":[]}'), since: 0), isNull);
      expect(decodePullPage(Uint8List.fromList([0xff, 0xfe]), since: 0), isNull);
      expect(decodePullPage(_page([]), since: 5), isNull, reason: 'goes backwards');
    });
  });
}
