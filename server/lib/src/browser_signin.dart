/// Browser sign-in: an app gets the sync token by signing in to a sign-in
/// proxy (authentik, Authelia, oauth2-proxy…) in the browser, instead of
/// the token being typed or pasted (docs/SYNC_PROTOCOL.md, "Browser
/// sign-in").
///
/// The proxy guards `/signin` (the page) and lets `/v1/…` (the API, which
/// checks the bearer token itself) through. The app opens
/// `/signin?challenge=…&state=…&return=…`; the proxy signs the user in and
/// passes the request on with the user's name in a header
/// ([BrowserSignin.userHeader], e.g. `X-authentik-username`), which only the
/// proxy can set. The page asks "Allow Len to sync as `user`?"; on Allow
/// the server issues a one-time code bound to the app's challenge and the
/// page hands it to the app: a redirect to its loopback listener
/// (`http://127.0.0.1:PORT/callback`, desktops), to `len://signin`
/// (Android), or shown to copy (browsers). The app trades the code and its
/// verifier for the token at `POST /v1/signin/token` (PKCE, RFC 7636), so
/// a code caught on the way (another app claiming `len://`, a log) is
/// worthless.
library;

import 'dart:convert';
import 'dart:io' show HttpStatus, stderr;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

/// `/signin` (the page, behind the proxy's sign-in).
const signinPath = 'signin';

/// `/v1/signin/token` (the code's exchange; let through by the proxy).
const signinTokenPath = 'v1/signin/token';

/// How long a code from the page can be traded for the token.
const defaultSigninCodeLifetime = Duration(minutes: 5);

/// Codes issued on Allow and not yet traded: random, single-use,
/// short-lived and bound to the challenge of the app that asked.
class SigninCodes {
  SigninCodes({this.lifetime = defaultSigninCodeLifetime, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration lifetime;
  final DateTime Function() _now;
  final Map<String, ({String challenge, DateTime expiry})> _codes = {};
  final _random = Random.secure();

  /// Codes beyond this many outstanding drop the oldest.
  static const maxOutstanding = 100;

  /// A new code for the app whose verifier hashes to [challenge].
  String issue(String challenge) {
    final now = _now();
    _codes.removeWhere((_, c) => !now.isBefore(c.expiry));
    while (_codes.length >= maxOutstanding) {
      _codes.remove(_codes.keys.first);
    }
    final code = _base64Url([for (var i = 0; i < 24; i++) _random.nextInt(256)]);
    _codes[code] = (challenge: challenge, expiry: now.add(lifetime));
    return code;
  }

  /// Whether [code] is valid and [verifier] is the one its challenge was
  /// made from; the code is used up either way.
  bool redeem(String code, String verifier) {
    final entry = _codes.remove(code);
    if (entry == null || !_now().isBefore(entry.expiry)) return false;
    return _constantTimeEquals(utf8.encode(challengeOf(verifier)), utf8.encode(entry.challenge));
  }
}

/// The S256 challenge of [verifier]: base64url (unpadded) of its SHA-256.
String challengeOf(String verifier) => _base64Url(sha256.convert(ascii.encode(verifier)).bytes);

String _base64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Where the page hands the code to.
enum SigninReturn {
  /// A redirect to the app's listener, `http://127.0.0.1:PORT/callback`.
  loopback,

  /// A link to `len://signin` (Android).
  app,

  /// Shown on the page, to copy into the app.
  code,
}

/// What the app asked for, from the page's query or its form.
class SigninRequest {
  const SigninRequest({
    required this.challenge,
    required this.state,
    required this.returnTo,
    this.port,
    this.device,
  });

  final String challenge;
  final String state;
  final SigninReturn returnTo;

  /// The loopback listener's port ([SigninReturn.loopback] only).
  final int? port;

  /// The app's name for the device ("Len on Linux"), shown on the page.
  final String? device;

  static final _challenge = RegExp(r'^[A-Za-z0-9_-]{43}$');
  static final _state = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

  /// The request [params] describe, or why they don't.
  static ({SigninRequest? request, String? error}) parse(Map<String, String> params) {
    final challenge = params['challenge'] ?? '';
    final state = params['state'] ?? '';
    if (!_challenge.hasMatch(challenge)) return (request: null, error: 'bad challenge');
    if (!_state.hasMatch(state)) return (request: null, error: 'bad state');
    final returnTo = SigninReturn.values.asNameMap()[params['return']];
    if (returnTo == null) return (request: null, error: 'bad return');
    int? port;
    if (returnTo == SigninReturn.loopback) {
      port = int.tryParse(params['port'] ?? '');
      if (port == null || port < 1 || port > 65535 || '$port' != params['port']) {
        return (request: null, error: 'bad port');
      }
    }
    var device = params['device']?.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    if (device != null && device.length > 64) device = device.substring(0, 64);
    return (
      request: SigninRequest(
        challenge: challenge,
        state: state,
        returnTo: returnTo,
        port: port,
        device: (device == null || device.isEmpty) ? null : device,
      ),
      error: null,
    );
  }

  Map<String, String> get fields => {
    'challenge': challenge,
    'state': state,
    'return': returnTo.name,
    if (port != null) 'port': '$port',
    'device': ?device,
  };

  /// Where the app hears the answer ([params]: `code` or `error`, plus
  /// the state), or null when it is shown on the page.
  Uri? target(Map<String, String> params) {
    final query = {...params, 'state': state};
    return switch (returnTo) {
      SigninReturn.loopback => Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: '/callback',
        queryParameters: query,
      ),
      SigninReturn.app => Uri(scheme: 'len', host: 'signin', queryParameters: query),
      SigninReturn.code => null,
    };
  }
}

/// The sign-in's routes: `GET`/`POST /signin` and `POST /v1/signin/token`.
class BrowserSignin {
  BrowserSignin({required this.userHeader, required this.token, SigninCodes? codes})
    : codes = codes ?? SigninCodes();

  /// The header the sign-in proxy passes the signed-in user's name in
  /// (`LEN_SIGNIN_USER_HEADER`); a request without it did not come
  /// through the proxy's sign-in.
  final String userHeader;

  /// What the app gets: the server's `LEN_SYNC_TOKEN`.
  final String token;

  final SigninCodes codes;

  String? _user(Request request) {
    final user = request.headers[userHeader.toLowerCase()]?.trim();
    return (user == null || user.isEmpty) ? null : user;
  }

  /// `GET /signin`: asks the user to allow the app.
  Response page(Request request) {
    final user = _user(request);
    if (user == null) return _notThroughProxy();
    final parsed = SigninRequest.parse(request.url.queryParameters);
    final signin = parsed.request;
    if (signin == null) {
      return _page(
        HttpStatus.badRequest,
        'This sign-in link is broken',
        '<p>Start again from Len: Settings → Sync → Sign in with browser.</p>'
            '<p class="small">(${_escape(parsed.error!)})</p>',
      );
    }
    final device = signin.device == null ? 'Len' : _escape(signin.device!);
    final hidden = [
      for (final MapEntry(:key, :value) in signin.fields.entries)
        '<input type="hidden" name="${_escape(key)}" value="${_escape(value)}">',
    ].join();
    return _page(
      HttpStatus.ok,
      'Allow $device to sync?',
      '<p>$device asks to sync with this server. You are signed in as '
          '<strong>${_escape(user)}</strong>.</p>'
          '<p>Allow it only if you just started signing in from Len.</p>'
          '<form method="post" action="$signinPath">$hidden'
          '<button type="submit" name="action" value="allow" class="primary" autofocus>'
          'Allow</button> '
          '<button type="submit" name="action" value="cancel">Cancel</button></form>',
    );
  }

  /// `POST /signin`: the page's Allow or Cancel.
  Future<Response> answer(Request request) async {
    final user = _user(request);
    if (user == null) return _notThroughProxy();
    if (!_sameOrigin(request)) {
      return _page(
        HttpStatus.forbidden,
        'Sign-in refused',
        '<p>This request did not come from the sign-in page. Start again from Len.</p>',
      );
    }
    final contentType = request.headers['content-type']?.toLowerCase() ?? '';
    if (!contentType.startsWith('application/x-www-form-urlencoded') ||
        (request.contentLength ?? 0) > 4096) {
      return _page(HttpStatus.badRequest, 'Sign-in refused', '<p>Start again from Len.</p>');
    }
    final Map<String, String> form;
    try {
      form = Uri.splitQueryString(await request.readAsString());
    } on FormatException {
      return _page(HttpStatus.badRequest, 'Sign-in refused', '<p>Start again from Len.</p>');
    }
    final signin = SigninRequest.parse(form).request;
    if (signin == null) {
      return _page(HttpStatus.badRequest, 'Sign-in refused', '<p>Start again from Len.</p>');
    }
    if (form['action'] != 'allow') {
      return _handOver(
        signin,
        {'error': 'cancelled'},
        title: 'Cancelled',
        text: 'Nothing was sent to Len.',
      );
    }
    final code = codes.issue(signin.challenge);
    stderr.writeln(
      'len-sync: browser sign-in allowed for ${_printable(user)}'
      '${signin.device == null ? '' : ' (${_printable(signin.device!)})'}',
    );
    return _handOver(
      signin,
      {'code': code},
      title: 'Signed in',
      text: 'Len finishes connecting by itself; you can close this page.',
      code: code,
    );
  }

  /// `POST /v1/signin/token` `{"code", "verifier"}`: the token, once.
  Future<Response> exchange(Request request) async {
    final Object? body;
    try {
      if ((request.contentLength ?? 0) > 4096) throw const FormatException();
      body = jsonDecode(await request.readAsString());
    } on FormatException {
      return _json(HttpStatus.badRequest, {'error': 'body must be {"code", "verifier"}'});
    }
    final code = body is Map ? body['code'] : null;
    final verifier = body is Map ? body['verifier'] : null;
    if (code is! String || verifier is! String || !_verifier.hasMatch(verifier)) {
      return _json(HttpStatus.badRequest, {'error': 'body must be {"code", "verifier"}'});
    }
    if (!codes.redeem(code.trim(), verifier)) {
      return _json(HttpStatus.unauthorized, {
        'error': 'sign-in code unknown, used or expired: sign in again',
      });
    }
    return _json(HttpStatus.ok, {'token': token});
  }

  static final _verifier = RegExp(r'^[A-Za-z0-9._~-]{43,128}$');

  /// Whether a form post comes from the page itself: its `Origin` names
  /// the host it was sent to (`Host`, or `X-Forwarded-Host` from a proxy
  /// that rewrites it), or, without one, `Sec-Fetch-Site: same-origin`.
  static bool _sameOrigin(Request request) {
    final origin = request.headers['origin'];
    if (origin == null) return request.headers['sec-fetch-site'] == 'same-origin';
    final uri = Uri.tryParse(origin);
    if (uri == null || uri.host.isEmpty) return false;
    final originHost = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    bool matches(String? host) {
      if (host == null) return false;
      final h = host.split(',').first.trim().toLowerCase();
      return h == originHost.toLowerCase() ||
          (!uri.hasPort && h.replaceFirst(RegExp(r':(80|443)$'), '') == originHost.toLowerCase());
    }

    return matches(request.headers['host']) || matches(request.headers['x-forwarded-host']);
  }

  /// The answer's page: sends the app [params] by itself (loopback, app)
  /// and shows the [code] to copy, as a fallback or the only way (code).
  Response _handOver(
    SigninRequest signin,
    Map<String, String> params, {
    required String title,
    required String text,
    String? code,
  }) {
    final target = signin.target(params);
    final nonce = target == null
        ? null
        : _base64Url([for (var i = 0; i < 16; i++) Random.secure().nextInt(256)]);
    final buffer = StringBuffer('<p>${_escape(text)}</p>');
    if (target != null && nonce != null) {
      final href = _escape(target.toString());
      buffer.write(
        '<p><a class="button primary" id="return" href="$href">Return to Len</a></p>'
        '<script nonce="$nonce">location.replace(${jsonEncode(target.toString()).replaceAll('<', r'\u003c')});</script>',
      );
    }
    if (code != null) {
      final where = target == null
          ? 'Paste this code into Len:'
          : 'If Len doesn’t continue, paste this code into it:';
      buffer.write(
        '<p class="small">$where</p><p><code id="code">${_escape(code)}</code></p>'
        '<p class="small">It works once, within ${codes.lifetime.inMinutes} minutes, and only '
        'in the Len that asked.</p>',
      );
    }
    return _page(HttpStatus.ok, title, buffer.toString(), nonce: nonce);
  }

  Response _notThroughProxy() => _page(
    HttpStatus.forbidden,
    'Sign in through the proxy',
    '<p>This page only works behind the sign-in proxy, which passes the user in '
        '<code>${_escape(userHeader)}</code>. Check that the proxy guards '
        '<code>/$signinPath</code>.</p>',
  );
}

Response _page(int status, String title, String body, {String? nonce}) {
  final escaped = _escape(title);
  return Response(
    status,
    body:
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>$escaped · Len sync</title><style>$_style</style></head>'
        '<body><main><h1>$escaped</h1>$body</main></body></html>',
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'x-frame-options': 'DENY',
      'referrer-policy': 'no-referrer',
      'content-security-policy':
          "default-src 'none'; style-src 'unsafe-inline'; "
          "script-src ${nonce == null ? "'none'" : "'nonce-$nonce'"}; "
          "form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
    },
  );
}

const _style =
    'body{font:16px/1.5 system-ui,sans-serif;margin:0;padding:48px 16px;color:#1b1b1f;'
    'background:#fafaf7}main{max-width:28rem;margin:auto}h1{font-size:1.4rem;font-weight:600}'
    'button,.button{font:inherit;padding:8px 16px;border-radius:8px;border:1px solid #c8c8c0;'
    'background:none;color:inherit;text-decoration:none;display:inline-block;cursor:pointer}'
    '.primary{background:#1b1b1f;color:#fff;border-color:#1b1b1f}.small{font-size:.85rem;'
    'color:#5c5c63}code{font-size:1rem;word-break:break-all;user-select:all}'
    '@media(prefers-color-scheme:dark){body{background:#151517;color:#ececec}'
    '.primary{background:#ececec;color:#151517;border-color:#ececec}.small{color:#a5a5ad}}';

/// [s] for HTML text and double-quoted attributes.
String _escape(String s) => const HtmlEscape(HtmlEscapeMode.attribute).convert(s);

/// [s] without control characters, for a log line.
String _printable(String s) => s.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '?');

Response _json(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'},
);
