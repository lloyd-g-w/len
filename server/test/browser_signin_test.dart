import 'dart:convert';
import 'dart:io';

import 'package:len_sync_server/len_sync_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const token = 'test-token-0123456789abcdef';
const userHeader = 'X-authentik-username';
const verifier = 'verifier-0123456789-abcdefghijklmnopqrstuvwxyz';
const state = 'state-0123456789abcdef';

void main() {
  late RecordStore store;
  late Directory blobDir;
  late DateTime now;

  setUp(() {
    store = RecordStore.inMemory();
    blobDir = Directory.systemTemp.createTempSync('len_signin_test_');
    now = DateTime(2026, 11, 14, 12);
  });
  tearDown(() {
    store.close();
    blobDir.deleteSync(recursive: true);
  });

  Handler handler({String? header = userHeader}) => buildHandler(
    store: store,
    blobs: BlobStore.open(blobDir.path),
    token: token,
    signinUserHeader: header,
    signinCodes: SigninCodes(now: () => now),
  );

  final challenge = challengeOf(verifier);

  Map<String, String> query({String returnTo = 'loopback', String? port = '43123'}) => {
    'challenge': challenge,
    'state': state,
    'return': returnTo,
    'port': ?port,
    'device': 'Len on Linux',
  };

  Future<Response> get(Handler h, Map<String, String> params, {String? user = 'lloyd'}) =>
      Future.value(
        h(
          Request(
            'GET',
            Uri.https('sync.example.com', '/signin', params),
            headers: {userHeader: ?user},
          ),
        ),
      );

  Future<Response> post(
    Handler h,
    Map<String, String> form, {
    String? user = 'lloyd',
    String? origin = 'https://sync.example.com',
    Map<String, String> extra = const {},
  }) => Future.value(
    h(
      Request(
        'POST',
        Uri.https('sync.example.com', '/signin'),
        headers: {
          'host': 'sync.example.com',
          'content-type': 'application/x-www-form-urlencoded',
          userHeader: ?user,
          'origin': ?origin,
          ...extra,
        },
        body: Uri(queryParameters: form).query,
      ),
    ),
  );

  Future<Response> exchange(Handler h, Object body) => Future.value(
    h(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/signin/token'),
        headers: {'content-type': 'application/json'},
        body: body is String ? body : jsonEncode(body),
      ),
    ),
  );

  String codeIn(String html) => RegExp(r'<code id="code">([^<]+)</code>').firstMatch(html)![1]!;

  Future<String> allow(Handler h, {String returnTo = 'loopback', String? port = '43123'}) async {
    final r = await post(h, {...query(returnTo: returnTo, port: port), 'action': 'allow'});
    expect(r.statusCode, 200);
    return codeIn(await r.readAsString());
  }

  group('off (no LEN_SIGNIN_USER_HEADER)', () {
    test('no sign-in routes; health says so', () async {
      final h = handler(header: null);
      expect((await get(h, query())).statusCode, 404);
      expect((await post(h, {...query(), 'action': 'allow'})).statusCode, 404);
      expect((await exchange(h, {'code': 'x', 'verifier': verifier})).statusCode, 404);
      final health = await h(Request('GET', Uri.parse('http://localhost/v1/health')));
      expect(jsonDecode(await health.readAsString())['signin'], false);
    });
  });

  group('page', () {
    test('health says sign-in is on', () async {
      final health = await handler()(Request('GET', Uri.parse('http://localhost/v1/health')));
      expect(jsonDecode(await health.readAsString())['signin'], true);
    });

    test('asks to allow the device as the proxy\'s user', () async {
      final r = await get(handler(), query(), user: '<b>lloyd</b>');
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], startsWith('text/html'));
      expect(r.headers['cache-control'], 'no-store');
      expect(r.headers['x-frame-options'], 'DENY');
      expect(r.headers['content-security-policy'], contains("frame-ancestors 'none'"));
      final html = await r.readAsString();
      expect(html, contains('Allow Len on Linux to sync?'));
      expect(html, contains('&lt;b&gt;lloyd&lt;/b&gt;'));
      expect(html, isNot(contains('<b>lloyd')));
      expect(html, contains('name="challenge" value="$challenge"'));
      expect(html, contains('name="port" value="43123"'));
      expect(html, isNot(contains(token)));
    });

    test('without the proxy\'s user header: refused', () async {
      final r = await get(handler(), query(), user: null);
      expect(r.statusCode, 403);
      expect(await r.readAsString(), contains(userHeader));
    });

    test('a broken link: 400', () async {
      final h = handler();
      for (final params in [
        {...query(), 'challenge': 'short'},
        {...query(), 'state': 'x'},
        {...query(), 'return': 'elsewhere'},
        query(port: null),
        query(port: '0'),
        query(port: '70000'),
        query(port: '+80'),
      ]) {
        expect((await get(h, params)).statusCode, 400, reason: '$params');
      }
      // Only loopback needs a port.
      expect((await get(h, query(returnTo: 'app', port: null))).statusCode, 200);
    });
  });

  group('answer', () {
    test('loopback: goes to the listener with a code, shows it too', () async {
      final r = await post(handler(), {...query(), 'action': 'allow'});
      expect(r.statusCode, 200);
      final html = await r.readAsString();
      final code = codeIn(html);
      final target = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: 43123,
        path: '/callback',
        queryParameters: {'code': code, 'state': state},
      ).toString();
      expect(html, contains('location.replace(${jsonEncode(target)})'));
      final nonce = RegExp(r'<script nonce="([^"]+)">').firstMatch(html)![1]!;
      expect(r.headers['content-security-policy'], contains("script-src 'nonce-$nonce'"));
      expect(html, isNot(contains(token)));
    });

    test('app: goes to len://signin', () async {
      final r = await post(handler(), {...query(returnTo: 'app', port: null), 'action': 'allow'});
      final html = await r.readAsString();
      final code = codeIn(html);
      expect(
        html,
        contains(jsonEncode(Uri.parse('len://signin?code=$code&state=$state').toString())),
      );
    });

    test('code: only shown', () async {
      final r = await post(handler(), {...query(returnTo: 'code', port: null), 'action': 'allow'});
      final html = await r.readAsString();
      expect(codeIn(html), isNotEmpty);
      expect(html, isNot(contains('<script')));
      expect(r.headers['content-security-policy'], contains("script-src 'none'"));
    });

    test('cancel tells the app, issues no code', () async {
      final r = await post(handler(), {...query(), 'action': 'cancel'});
      final html = await r.readAsString();
      expect(html, contains('error=cancelled&state=$state'));
      expect(html, isNot(contains('<code id="code">')));
    });

    test('only the page\'s own posts', () async {
      final h = handler();
      final form = {...query(), 'action': 'allow'};
      expect((await post(h, form, origin: 'https://evil.example')).statusCode, 403);
      expect((await post(h, form, origin: 'null')).statusCode, 403);
      expect((await post(h, form, origin: null)).statusCode, 403);
      expect(
        (await post(h, form, origin: null, extra: {'sec-fetch-site': 'cross-site'})).statusCode,
        403,
      );
      expect(
        (await post(h, form, origin: null, extra: {'sec-fetch-site': 'same-origin'})).statusCode,
        200,
      );
      // A proxy that rewrites Host sets X-Forwarded-Host.
      expect(
        (await post(
          h,
          form,
          extra: {'host': 'len-sync:8080', 'x-forwarded-host': 'sync.example.com'},
        )).statusCode,
        200,
      );
      expect((await post(h, form, user: null)).statusCode, 403);
    });
  });

  group('exchange', () {
    test('the code and verifier get the token, once, without a bearer token', () async {
      final h = handler();
      final code = await allow(h);
      final r = await exchange(h, {'code': code, 'verifier': verifier});
      expect(r.statusCode, 200);
      expect(r.headers['cache-control'], 'no-store');
      expect(jsonDecode(await r.readAsString()), {'token': token});
      expect((await exchange(h, {'code': code, 'verifier': verifier})).statusCode, 401);
    });

    test('a wrong verifier uses the code up', () async {
      final h = handler();
      final code = await allow(h);
      final wrong = '${verifier}x';
      expect((await exchange(h, {'code': code, 'verifier': wrong})).statusCode, 401);
      expect((await exchange(h, {'code': code, 'verifier': verifier})).statusCode, 401);
    });

    test('an expired code', () async {
      final h = handler();
      final code = await allow(h);
      now = now.add(defaultSigninCodeLifetime);
      expect((await exchange(h, {'code': code, 'verifier': verifier})).statusCode, 401);
    });

    test('malformed: 400', () async {
      final h = handler();
      for (final body in [
        'not json',
        '[]',
        {'code': 'x'},
        {'code': 'x', 'verifier': 'short'},
        {'code': 1, 'verifier': verifier},
      ]) {
        expect((await exchange(h, body)).statusCode, 400, reason: '$body');
      }
    });
  });

  group('config', () {
    test('LEN_SIGNIN_USER_HEADER', () {
      final env = {'LEN_SYNC_TOKEN': token};
      expect(Config.fromEnvironment(env).signinUserHeader, isNull);
      expect(
        Config.fromEnvironment({
          ...env,
          'LEN_SIGNIN_USER_HEADER': ' X-authentik-username ',
        }).signinUserHeader,
        'X-authentik-username',
      );
      for (final bad in ['X user', 'X:y', 'Authorization', 'cookie']) {
        expect(
          () => Config.fromEnvironment({...env, 'LEN_SIGNIN_USER_HEADER': bad}),
          throwsA(isA<ConfigException>()),
          reason: bad,
        );
      }
    });
  });
}
