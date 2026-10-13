/// A sync setup carried from a connected device to a new one, so its
/// server URL and access token aren't typed again:
/// `len://sync?url=<server URL>&token=<access token>`. Shown as a QR code
/// and a link in Settings on a connected device; opened on Android (the
/// `len` scheme's intent filter) or pasted into the Server URL field.
///
/// The token is a secret: anyone with the link can sync with the server.
class SyncSetupLink {
  const SyncSetupLink({required this.url, required this.token});

  static const String scheme = 'len';
  static const String host = 'sync';

  final String url;
  final String token;

  /// The link, its parts percent-encoded.
  String get link =>
      Uri(scheme: scheme, host: host, queryParameters: {'url': url, 'token': token}).toString();

  /// The setup [text] carries (surrounding whitespace allowed), or null if
  /// it isn't a sync setup link with a URL.
  static SyncSetupLink? parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || !uri.isScheme(scheme) || uri.host != host) return null;
    final url = uri.queryParameters['url']?.trim() ?? '';
    if (url.isEmpty) return null;
    return SyncSetupLink(url: url, token: uri.queryParameters['token'] ?? '');
  }

  @override
  bool operator ==(Object other) =>
      other is SyncSetupLink && other.url == url && other.token == token;

  @override
  int get hashCode => Object.hash(url, token);

  @override
  String toString() => 'SyncSetupLink($url)'; // Never the token.
}
