/// CORS middleware so browser clients (the Len web app) can call the API.
///
/// Auth is a bearer token, never cookies, so `Access-Control-Allow-Credentials`
/// is never sent and allowing any origin (`*`) is safe.
library;

import 'dart:io' show HttpStatus;

import 'package:shelf/shelf.dart';

/// Methods the API serves, advertised in preflight responses.
const corsAllowMethods = 'GET, HEAD, POST, PUT, OPTIONS';

/// Request headers clients may send, advertised in preflight responses.
const corsAllowHeaders = 'Authorization, Content-Type';

/// Response headers readable by browser scripts.
const corsExposeHeaders = 'Content-Length, Content-Type';

/// How long browsers may cache a preflight result, in seconds.
const corsMaxAge = 86400;

/// Which origins may access the API from a browser.
class CorsPolicy {
  /// Allows any origin (`Access-Control-Allow-Origin: *`).
  const CorsPolicy.any() : enabled = true, origins = null;

  /// Sends no CORS headers at all; browsers then block cross-origin access.
  const CorsPolicy.disabled() : enabled = false, origins = null;

  /// Allows only [origins] (e.g. `https://len.example.com`), which are
  /// matched case-insensitively against the request's `Origin` header.
  CorsPolicy.allowList(Iterable<String> origins)
    : enabled = true,
      origins = {for (final o in origins) o.toLowerCase()};

  /// Whether CORS headers are sent at all.
  final bool enabled;

  /// Allowed origins (lowercase), or `null` for any origin.
  final Set<String>? origins;

  /// Value for `Access-Control-Allow-Origin` given the request's [origin]
  /// header, or `null` if the request must get no CORS headers.
  String? allowOriginFor(String? origin) {
    if (!enabled) return null;
    final allowed = origins;
    if (allowed == null) return '*';
    if (origin == null || !allowed.contains(origin.toLowerCase())) return null;
    return origin;
  }
}

/// Middleware applying [policy]; place it outside the auth middleware.
///
/// `OPTIONS` requests are answered directly (no auth): 204 with the allow
/// headers if the origin is allowed, 403 without CORS headers otherwise.
/// All other responses, including errors, get `Access-Control-Allow-Origin`
/// and `Access-Control-Expose-Headers` if the origin is allowed. With an
/// allow-list every response carries `Vary: Origin`. A disabled policy
/// passes everything through unchanged.
Middleware corsMiddleware(CorsPolicy policy) {
  return (Handler inner) {
    if (!policy.enabled) return inner;
    final varies = policy.origins != null;
    return (Request request) async {
      final allowOrigin = policy.allowOriginFor(request.headers['origin']);
      if (request.method == 'OPTIONS') {
        if (allowOrigin == null) {
          return Response(HttpStatus.forbidden, headers: {if (varies) 'vary': 'Origin'});
        }
        return Response(
          HttpStatus.noContent,
          headers: {
            'access-control-allow-origin': allowOrigin,
            'access-control-allow-methods': corsAllowMethods,
            'access-control-allow-headers': corsAllowHeaders,
            'access-control-max-age': '$corsMaxAge',
            if (varies) 'vary': 'Origin',
          },
        );
      }
      final response = await inner(request);
      return response.change(
        headers: {
          if (allowOrigin != null) ...{
            'access-control-allow-origin': allowOrigin,
            'access-control-expose-headers': corsExposeHeaders,
          },
          if (varies) 'vary': _addVaryOrigin(response.headers['vary']),
        },
      );
    };
  };
}

/// Appends `Origin` to an existing `Vary` header value unless present.
String _addVaryOrigin(String? vary) {
  if (vary == null || vary.trim().isEmpty) return 'Origin';
  final parts = vary.split(',').map((p) => p.trim().toLowerCase());
  if (parts.contains('origin') || parts.contains('*')) return vary;
  return '$vary, Origin';
}
