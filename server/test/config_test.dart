import 'package:len_sync_server/len_sync_server.dart';
import 'package:test/test.dart';

void main() {
  const token = '0123456789abcdef';

  test('applies defaults', () {
    final c = Config.fromEnvironment({'LEN_SYNC_TOKEN': token});
    expect(c.token, token);
    expect(c.dbPath, '/data/len.db');
    expect(c.host, '0.0.0.0');
    expect(c.port, 8080);
    expect(c.blobDir, '/data/blobs');
    expect(c.blobMaxBytes, 209715200);
    expect(c.blobIdleTimeout, const Duration(seconds: 60));
  });

  test('reads LEN_BLOB_IDLE_TIMEOUT and rejects invalid values', () {
    final c = Config.fromEnvironment({'LEN_SYNC_TOKEN': token, 'LEN_BLOB_IDLE_TIMEOUT': '15'});
    expect(c.blobIdleTimeout, const Duration(seconds: 15));
    for (final value in ['abc', '0', '-1', '1.5']) {
      expect(
        () => Config.fromEnvironment({'LEN_SYNC_TOKEN': token, 'LEN_BLOB_IDLE_TIMEOUT': value}),
        throwsA(isA<ConfigException>()),
        reason: value,
      );
    }
  });

  test('blob dir defaults to blobs/ next to the database', () {
    final c = Config.fromEnvironment({'LEN_SYNC_TOKEN': token, 'LEN_DB_PATH': '/srv/len/x.db'});
    expect(c.blobDir, '/srv/len/blobs');
    final relative = Config.fromEnvironment({'LEN_SYNC_TOKEN': token, 'LEN_DB_PATH': 'x.db'});
    expect(relative.blobDir, './blobs');
  });

  test('reads blob overrides', () {
    final c = Config.fromEnvironment({
      'LEN_SYNC_TOKEN': token,
      'LEN_BLOB_DIR': '/mnt/blobs',
      'LEN_BLOB_MAX_BYTES': '1024',
    });
    expect(c.blobDir, '/mnt/blobs');
    expect(c.blobMaxBytes, 1024);
  });

  test('rejects invalid LEN_BLOB_MAX_BYTES', () {
    for (final value in ['abc', '0', '-5', '1.5']) {
      expect(
        () => Config.fromEnvironment({'LEN_SYNC_TOKEN': token, 'LEN_BLOB_MAX_BYTES': value}),
        throwsA(isA<ConfigException>()),
        reason: value,
      );
    }
  });

  test('reads overrides', () {
    final c = Config.fromEnvironment({
      'LEN_SYNC_TOKEN': token,
      'LEN_DB_PATH': '/tmp/x.db',
      'HOST': '127.0.0.1',
      'PORT': '9000',
    });
    expect(c.dbPath, '/tmp/x.db');
    expect(c.host, '127.0.0.1');
    expect(c.port, 9000);
  });

  test('rejects missing, empty or short token', () {
    for (final env in [
      <String, String>{},
      {'LEN_SYNC_TOKEN': ''},
      {'LEN_SYNC_TOKEN': '   '},
      {'LEN_SYNC_TOKEN': 'short-token-123'},
    ]) {
      expect(() => Config.fromEnvironment(env), throwsA(isA<ConfigException>()));
    }
  });

  group('LEN_CORS_ORIGINS', () {
    CorsPolicy corsOf(String? value) =>
        Config.fromEnvironment({'LEN_SYNC_TOKEN': token, 'LEN_CORS_ORIGINS': ?value}).cors;

    test('unset, empty or * allows any origin', () {
      for (final value in [null, '', '  ', '*', ' * ']) {
        final cors = corsOf(value);
        expect(cors.enabled, isTrue, reason: value);
        expect(cors.origins, isNull, reason: value);
      }
    });

    test('none disables CORS', () {
      expect(corsOf('none').enabled, isFalse);
      expect(corsOf('NONE').enabled, isFalse);
    });

    test('reads a comma-separated allow-list', () {
      final cors = corsOf(' https://len.example.com, http://localhost:5173 ,');
      expect(cors.enabled, isTrue);
      expect(cors.origins, {'https://len.example.com', 'http://localhost:5173'});
    });

    test('rejects invalid origins', () {
      for (final value in [
        'len.example.com',
        'https://len.example.com/',
        'https://len.example.com/app',
        'ftp://len.example.com',
        'https://a.example, *',
        'https://a.example, none',
        ',',
      ]) {
        expect(() => corsOf(value), throwsA(isA<ConfigException>()), reason: value);
      }
    });
  });

  test('rejects invalid port', () {
    for (final port in ['abc', '0', '70000']) {
      expect(
        () => Config.fromEnvironment({'LEN_SYNC_TOKEN': token, 'PORT': port}),
        throwsA(isA<ConfigException>()),
      );
    }
  });
}
