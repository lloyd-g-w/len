import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Where the server's sign-in page hands its one-time code back to Len
/// (docs/SYNC_PROTOCOL.md, "Browser sign-in"; the server's
/// `browser_signin.dart`).
enum SigninReturn {
  /// To a listener of this app on `http://127.0.0.1:PORT/callback`
  /// (desktops; RFC 8252's loopback redirect).
  loopback,

  /// To a `len://signin?…` link this app opens (Android).
  app,

  /// Shown on the page, to paste into Len (browsers, which can neither
  /// listen nor be linked to).
  code,
}

/// One browser sign-in: the app opens [url] in the browser, the user signs
/// in to the sign-in proxy (authentik…) in front of the server and allows
/// Len, and the page hands back a one-time code ([codeFrom]); the app
/// trades it, with [verifier], for the access token (`POST
/// /v1/signin/token`). Only this app knows [verifier] (the page sees its
/// SHA-256, [challenge]: PKCE, RFC 7636), so a code caught on its way, by
/// another app that claims `len://` or a browser's history, is worthless;
/// [state] ties answers to this sign-in.
class BrowserSignin {
  BrowserSignin({
    required String serverUrl,
    required this.returnTo,
    this.port,
    this.device,
    Random? random,
  }) : assert((returnTo == SigninReturn.loopback) == (port != null)),
       _server = _withSlash(serverUrl),
       verifier = _randomText(random ?? Random.secure(), 32),
       state = _randomText(random ?? Random.secure(), 16);

  /// The server's address (`https://sync.example.com/`).
  final Uri _server;

  final SigninReturn returnTo;

  /// The loopback listener's port ([SigninReturn.loopback]).
  final int? port;

  /// How the page names this device ("Len on Linux").
  final String? device;

  /// The secret the code is traded with: 43 base64url characters.
  final String verifier;

  /// Ties the page's answer to this sign-in.
  final String state;

  /// The S256 challenge of [verifier]: what the page binds its code to.
  String get challenge => _base64Url(sha256.convert(ascii.encode(verifier)).bytes);

  /// The server's sign-in page, to open in the browser.
  Uri get url => _server
      .resolve('signin')
      .replace(
        queryParameters: {
          'challenge': challenge,
          'state': state,
          'return': returnTo.name,
          if (port != null) 'port': '$port',
          'device': ?device,
        },
      );

  /// What an answer says: a [code], or that the user cancelled
  /// ([cancelled]); null for anything else, an answer to another sign-in
  /// included.
  ///
  /// [text] is a link the page sent (`len://signin?code=…&state=…`, the
  /// listener's `http://127.0.0.1:…/callback?…`) or what the user pasted:
  /// the bare code as the page shows it, or one of those links.
  SigninAnswer? answerFrom(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      final params = uri.queryParameters;
      if (params['state'] != state) return null;
      if (params['error'] != null) return const SigninAnswer.cancelled();
      final code = params['code'];
      return code == null || !_code.hasMatch(code) ? null : SigninAnswer.code(code);
    }
    return _code.hasMatch(trimmed) ? SigninAnswer.code(trimmed) : null;
  }

  static final _code = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

  static Uri _withSlash(String url) {
    final uri = Uri.parse(url.trim());
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }

  static String _randomText(Random random, int bytes) =>
      _base64Url([for (var i = 0; i < bytes; i++) random.nextInt(256)]);

  static String _base64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}

/// The sign-in page's answer: a code to trade for the token, or Cancel.
class SigninAnswer {
  const SigninAnswer.code(String this.code);
  const SigninAnswer.cancelled() : code = null;

  /// Null when the user cancelled.
  final String? code;

  bool get cancelled => code == null;

  @override
  bool operator ==(Object other) => other is SigninAnswer && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => cancelled ? 'SigninAnswer.cancelled' : 'SigninAnswer.code';
}
