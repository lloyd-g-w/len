import 'dart:convert';

/// [fragment] as Windows' "HTML Format" (CF_HTML, added in Len's copy): a
/// header giving the UTF-8 byte offsets of the document and of the
/// fragment between `<!--StartFragment-->` and `<!--EndFragment-->`.
String encodeCfHtml(String fragment) {
  const prefix = '<html><body>\r\n<!--StartFragment-->';
  const suffix = '<!--EndFragment-->\r\n</body></html>';
  String header(int startHtml, int endHtml, int startFragment, int endFragment) =>
      'Version:0.9\r\n'
      'StartHTML:${_pad(startHtml)}\r\n'
      'EndHTML:${_pad(endHtml)}\r\n'
      'StartFragment:${_pad(startFragment)}\r\n'
      'EndFragment:${_pad(endFragment)}\r\n';
  final headerLength = header(0, 0, 0, 0).length; // ASCII: bytes = units.
  final startFragment = headerLength + prefix.length;
  final endFragment = startFragment + utf8.encode(fragment).length;
  final endHtml = endFragment + suffix.length;
  return '${header(headerLength, endHtml, startFragment, endFragment)}'
      '$prefix$fragment$suffix';
}

String _pad(int n) => n.toString().padLeft(10, '0');
