import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:len/features/documents/import/incoming_files.dart';
import 'package:len/features/settings/browser_signin_dialog.dart';
import 'package:len/platform/signin_listener.dart';
import 'package:len/sync/browser_signin.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len_sync_server/len_sync_server.dart' as server;
import 'package:shelf/shelf_io.dart' as shelf_io;

const token = 'signin-test-token-0123456789';
const userHeader = 'X-authentik-username';

/// Tests run with the test binding's HTTP stub (every request answered
/// 400): real connections for this test.
void realSockets() {
  final stub = HttpOverrides.current;
  HttpOverrides.global = null;
  addTearDown(() => HttpOverrides.global = stub);
}

void main() {
  group('BrowserSignin', () {
    test('the page\'s URL carries the S256 challenge of a fresh verifier', () {
      final a = BrowserSignin(
        serverUrl: 'https://sync.example.com/len',
        returnTo: SigninReturn.loopback,
        port: 4321,
        device: 'Len on Linux',
      );
      final b = BrowserSignin(serverUrl: 'https://sync.example.com', returnTo: SigninReturn.app);
      expect(a.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(a.verifier, isNot(b.verifier));
      expect(a.state, isNot(b.state));
      // The server computes the same challenge.
      expect(a.challenge, server.challengeOf(a.verifier));
      expect(a.url.toString(), startsWith('https://sync.example.com/len/signin?'));
      expect(a.url.queryParameters, {
        'challenge': a.challenge,
        'state': a.state,
        'return': 'loopback',
        'port': '4321',
        'device': 'Len on Linux',
      });
      expect(b.url.queryParameters.containsKey('port'), isFalse);
      expect(b.url.queryParameters['return'], 'app');
    });

    test('reads answers for this sign-in only', () {
      final signin = BrowserSignin(
        serverUrl: 'https://sync.example.com',
        returnTo: SigninReturn.app,
        random: Random(1),
      );
      const code = 'abcdefghijklmnop0123456789_-ABCD';
      final state = signin.state;
      expect(
        signin.answerFrom('len://signin?code=$code&state=$state'),
        const SigninAnswer.code(code),
      );
      expect(
        signin.answerFrom('http://127.0.0.1:4321/callback?code=$code&state=$state'),
        const SigninAnswer.code(code),
      );
      expect(signin.answerFrom('  $code\n'), const SigninAnswer.code(code));
      expect(
        signin.answerFrom('len://signin?error=cancelled&state=$state'),
        const SigninAnswer.cancelled(),
      );
      // Another sign-in's answer, or not a code.
      expect(signin.answerFrom('len://signin?code=$code&state=other-state-0123456789'), isNull);
      expect(signin.answerFrom('len://signin?code=$code'), isNull);
      expect(signin.answerFrom('short'), isNull);
      expect(signin.answerFrom('has spaces in it, not a code'), isNull);
      expect(signin.answerFrom(''), isNull);
    });
  });

  group('with the real server', () {
    late server.RecordStore store;
    late Directory dir;
    late HttpServer http_;
    late String base;

    Future<void> serve({String? header = userHeader}) async {
      http_ = await shelf_io.serve(
        server.buildHandler(
          store: store,
          blobs: server.BlobStore.open('${dir.path}/blobs'),
          token: token,
          signinUserHeader: header,
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      base = 'http://127.0.0.1:${http_.port}';
    }

    setUp(() {
      realSockets();
      store = server.RecordStore.inMemory();
      dir = Directory.systemTemp.createTempSync('len-signin-');
    });
    tearDown(() async {
      await http_.close(force: true);
      store.close();
      dir.deleteSync(recursive: true);
    });

    /// What the browser does on the page, signed in to the proxy as
    /// lloyd: Allow. The page's answer (with the code).
    Future<String> allow(BrowserSignin signin) async {
      final page = await http.get(signin.url, headers: {userHeader: 'lloyd'});
      expect(page.statusCode, 200);
      final form = {
        for (final m in RegExp(r'name="(\w+)" value="([^"]*)"').allMatches(page.body)) m[1]!: m[2]!,
        'action': 'allow',
      };
      final answer = await http.post(
        Uri.parse('$base/signin'),
        headers: {userHeader: 'lloyd', 'origin': base},
        body: form,
      );
      expect(answer.statusCode, 200);
      return answer.body;
    }

    test('health says so; the code and verifier get the token once', () async {
      await serve();
      final api = SyncApi(baseUrl: base, token: '');
      addTearDown(api.close);
      expect((await api.serverInfo()).signin, isTrue);
      final signin = BrowserSignin(serverUrl: base, returnTo: SigninReturn.code);
      final page = await allow(signin);
      final code = RegExp(r'<code id="code">([^<]+)</code>').firstMatch(page)![1]!;
      final answer = signin.answerFrom(code)!;
      expect(await api.signinToken(code: answer.code!, verifier: signin.verifier), token);
      await expectLater(
        api.signinToken(code: answer.code!, verifier: signin.verifier),
        throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.auth)),
      );
      // The token works.
      expect(await SyncApi(baseUrl: base, token: token).check(), isA<ServerInfo>());
    });

    test('desktop: the page redirects to the loopback listener', () async {
      await serve();
      final listener = (await startSigninListener())!;
      addTearDown(listener.close);
      final heard = listener.callbacks.first;
      final signin = BrowserSignin(
        serverUrl: base,
        returnTo: SigninReturn.loopback,
        port: listener.port,
      );
      final page = await allow(signin);
      // The browser follows the page's script to the listener.
      final target = jsonDecode(
        RegExp(r'location\.replace\(("[^"]+")\)').firstMatch(page)![1]!.replaceAll(r'\u003c', '<'),
      ) as String;
      expect(Uri.parse(target).port, listener.port);
      final landing = await http.get(Uri.parse(target));
      expect(landing.body, contains('Len is finishing signing in'));
      final answer = signin.answerFrom(await heard)!;
      final api = SyncApi(baseUrl: base, token: '');
      addTearDown(api.close);
      expect(await api.signinToken(code: answer.code!, verifier: signin.verifier), token);
    });

    test('a server without browser sign-in', () async {
      await serve(header: null);
      final api = SyncApi(baseUrl: base, token: '');
      addTearDown(api.close);
      expect((await api.serverInfo()).signin, isFalse);
      await expectLater(
        api.signinToken(code: 'abcdefghijklmnop', verifier: 'v' * 43),
        throwsA(same(SyncException.noBrowserSignin)),
      );
    });
  });

  test('a login page in front of the API is named as such', () async {
    realSockets();
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    proxy.listen((request) {
      request.response
        ..headers.contentType = ContentType.html
        ..write('<!doctype html><title>authentik</title>')
        ..close();
    });
    final api = SyncApi(baseUrl: 'http://127.0.0.1:${proxy.port}', token: token);
    addTearDown(api.close);
    await expectLater(api.serverInfo(), throwsA(same(SyncException.signinPage)));
  });

  test('len://signin links reach a sign-in under way', () async {
    final incoming = IncomingFiles();
    addTearDown(incoming.dispose);
    final links = <String>[];
    incoming.signinLinks.listen(links.add);
    incoming
      ..addLink('len://signin?code=abc&state=def')
      ..addLink('len://sync?url=https://x.example&token=t')
      ..addLink('https://example.com/');
    await pumpEventQueue();
    expect(links, ['len://signin?code=abc&state=def']);
    expect(incoming.syncSetup.value?.url, 'https://x.example');
  });

  group('dialog', () {
    Future<Future<SigninAnswer?>> open(
      WidgetTester tester,
      BrowserSignin signin,
      Stream<String> answers,
      void Function() onOpen,
    ) async {
      late Future<SigninAnswer?> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showBrowserSigninDialog(
                context,
                signin: signin,
                answers: [answers],
                open: onOpen,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('opens the page, and ends on a link from it', (tester) async {
      final signin = BrowserSignin(serverUrl: 'https://s.example', returnTo: SigninReturn.app);
      final links = StreamController<String>.broadcast();
      addTearDown(links.close);
      var opened = 0;
      final result = await open(tester, signin, links.stream, () => opened++);
      expect(opened, 1);
      links.add('len://signin?code=abcdefghijklmnop&state=other-state-0123456789');
      await tester.pumpAndSettle();
      expect(find.text('Sign in with browser'), findsOneWidget);
      links.add('len://signin?code=abcdefghijklmnop&state=${signin.state}');
      await tester.pumpAndSettle();
      expect(find.text('Sign in with browser'), findsNothing);
      expect(await result, const SigninAnswer.code('abcdefghijklmnop'));
    });

    testWidgets('takes a pasted code; Open page again; Cancel', (tester) async {
      final signin = BrowserSignin(serverUrl: 'https://s.example', returnTo: SigninReturn.code);
      var opened = 0;
      var result = await open(tester, signin, const Stream.empty(), () => opened++);
      await tester.tap(find.text('Open page again'));
      expect(opened, 2);
      await tester.enterText(find.byType(TextField), 'no good');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('isn’t the code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' abcdefghijklmnop ');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(await result, const SigninAnswer.code('abcdefghijklmnop'));

      result = await open(tester, signin, const Stream.empty(), () {});
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });
}
