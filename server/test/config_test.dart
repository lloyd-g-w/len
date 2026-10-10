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
      expect(
        () => Config.fromEnvironment(env),
        throwsA(isA<ConfigException>()),
      );
    }
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
