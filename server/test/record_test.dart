import 'package:len_sync_server/len_sync_server.dart';
import 'package:test/test.dart';

Map<String, Object?> validJson() => {
  'collection': 'strokes',
  'id': 'abc',
  'updatedAt': 1760000000000,
  'deviceId': 'dev-1',
  'deleted': false,
  'data': {'tool': 'pen'},
};

Matcher get throwsValidation => throwsA(isA<RecordValidationException>());

void main() {
  group('SyncRecord.fromJson', () {
    test('parses a valid record', () {
      final r = SyncRecord.fromJson(validJson());
      expect(r.collection, 'strokes');
      expect(r.id, 'abc');
      expect(r.updatedAt, 1760000000000);
      expect(r.deviceId, 'dev-1');
      expect(r.deleted, isFalse);
      expect(r.data, {'tool': 'pen'});
      expect(r.seq, isNull);
    });

    test('ignores a client-supplied seq', () {
      final r = SyncRecord.fromJson({...validJson(), 'seq': 99});
      expect(r.seq, isNull);
      expect(r.toJson().containsKey('seq'), isFalse);
    });

    test('accepts null data', () {
      expect(SyncRecord.fromJson({...validJson(), 'data': null}).data, isNull);
    });

    test('drops data of deleted records', () {
      final r = SyncRecord.fromJson({...validJson(), 'deleted': true});
      expect(r.deleted, isTrue);
      expect(r.data, isNull);
    });

    test('rejects non-object input', () {
      expect(() => SyncRecord.fromJson([1]), throwsValidation);
      expect(() => SyncRecord.fromJson(null), throwsValidation);
    });

    for (final bad in ['', 'Notes', 'with-dash', 'a1', 'x' * 33, 42, null]) {
      test('rejects collection ${bad.toString()}', () {
        expect(
          () => SyncRecord.fromJson({...validJson(), 'collection': bad}),
          throwsValidation,
        );
      });
    }

    test('accepts collection of 32 chars with underscores', () {
      final c = '${'a' * 30}__';
      expect(
        SyncRecord.fromJson({...validJson(), 'collection': c}).collection,
        c,
      );
    });

    for (final key in ['id', 'deviceId']) {
      test('rejects empty, too long or non-string $key', () {
        for (final bad in ['', 'x' * 65, 7, null]) {
          expect(
            () => SyncRecord.fromJson({...validJson(), key: bad}),
            throwsValidation,
          );
        }
      });

      test('accepts 64-char $key', () {
        expect(
          () => SyncRecord.fromJson({...validJson(), key: 'x' * 64}),
          returnsNormally,
        );
      });
    }

    test('rejects non-integer updatedAt', () {
      for (final bad in [1.5, '1', null, true]) {
        expect(
          () => SyncRecord.fromJson({...validJson(), 'updatedAt': bad}),
          throwsValidation,
        );
      }
    });

    test('rejects non-boolean deleted', () {
      for (final bad in [0, 'false', null]) {
        expect(
          () => SyncRecord.fromJson({...validJson(), 'deleted': bad}),
          throwsValidation,
        );
      }
    });

    test('rejects non-object data', () {
      for (final bad in [
        [1, 2],
        'x',
        3,
        true,
      ]) {
        expect(
          () => SyncRecord.fromJson({...validJson(), 'data': bad}),
          throwsValidation,
        );
      }
    });

    test('rejects missing fields', () {
      for (final key in validJson().keys.where((k) => k != 'data')) {
        final json = validJson()..remove(key);
        expect(() => SyncRecord.fromJson(json), throwsValidation, reason: key);
      }
    });
  });

  group('SyncRecord.beats', () {
    final r = SyncRecord.fromJson(
      validJson(),
    ); // updatedAt 1760000000000, dev-1

    test('newer updatedAt wins regardless of deviceId', () {
      expect(r.beats(updatedAt: 1759999999999, deviceId: 'zzz'), isTrue);
      expect(r.beats(updatedAt: 1760000000001, deviceId: 'a'), isFalse);
    });

    test('equal updatedAt is broken by deviceId', () {
      expect(r.beats(updatedAt: 1760000000000, deviceId: 'dev-0'), isTrue);
      expect(r.beats(updatedAt: 1760000000000, deviceId: 'dev-2'), isFalse);
      expect(r.beats(updatedAt: 1760000000000, deviceId: 'dev-1'), isFalse);
    });
  });

  test('toJson roundtrips through fromJson', () {
    final json = validJson();
    expect(SyncRecord.fromJson(json).toJson(), json);
  });
}
