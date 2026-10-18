/// Code pages for RTF's `\'hh` escapes: the single-byte Windows ones
/// (Western 1252, Central European 1250, Cyrillic 1251 here; Greek,
/// Turkish, Hebrew, Arabic, Baltic, Vietnamese and Thai in
/// [codePageTables]), Mac Roman and the DOS ones. The double-byte East Asian
/// code pages ([isDoubleByte]) are not read.
library;

import 'rtf_code_page_tables.dart';

/// The character byte [b] stands for in code page [codePage] (Symbol-font
/// bytes, code page 42, keep their Latin-1 value except the bullet); null
/// for a byte of a double-byte code page (half a character, not read). An
/// unknown code page is read as Latin-1.
String? decodeCodePageByte(int b, int codePage) {
  if (b < 0x80) return String.fromCharCode(b);
  if (isDoubleByte(codePage)) return null;
  return switch (codePage) {
    1252 when b < 0xA0 => _cp1252[b - 0x80],
    1250 => _cp1250[b - 0x80],
    1251 => _cp1251[b - 0x80],
    42 when b == 0xB7 => '\u2022',
    _ => codePageTables[codePage]?[b - 0x80] ?? String.fromCharCode(b),
  };
}

/// Whether [codePage] is a double-byte East Asian one (Shift JIS, GBK,
/// Korean, Big5, Johab), whose characters take two `\'hh` escapes.
bool isDoubleByte(int codePage) => const {932, 936, 949, 950, 1361}.contains(codePage);

/// The Windows code page of an RTF `\fcharset`, or null where it is the
/// document's (`\ansicpg`).
int? codePageOfCharset(int charset) => switch (charset) {
  0 || 1 => null,
  2 => 42,
  77 => 10000,
  128 => 932,
  129 => 949,
  130 => 1361,
  134 => 936,
  136 => 950,
  161 => 1253,
  162 => 1254,
  163 => 1258,
  177 => 1255,
  178 => 1256,
  186 => 1257,
  204 => 1251,
  222 => 874,
  238 => 1250,
  _ => null,
};

// Bytes 0x80 – 0x9F of code page 1252 (the rest is Latin-1).
const _cp1252 =
    '\u20AC\u0081\u201A\u0192\u201E\u2026\u2020\u2021'
    '\u02C6\u2030\u0160\u2039\u0152\u008D\u017D\u008F'
    '\u0090\u2018\u2019\u201C\u201D\u2022\u2013\u2014'
    '\u02DC\u2122\u0161\u203A\u0153\u009D\u017E\u0178';

// Bytes 0x80 – 0xFF of code page 1250.
const _cp1250 =
    '\u20AC\u0081\u201A\u0083\u201E\u2026\u2020\u2021'
    '\u0088\u2030\u0160\u2039\u015A\u0164\u017D\u0179'
    '\u0090\u2018\u2019\u201C\u201D\u2022\u2013\u2014'
    '\u0098\u2122\u0161\u203A\u015B\u0165\u017E\u017A'
    '\u00A0\u02C7\u02D8\u0141\u00A4\u0104\u00A6\u00A7'
    '\u00A8\u00A9\u015E\u00AB\u00AC\u00AD\u00AE\u017B'
    '\u00B0\u00B1\u02DB\u0142\u00B4\u00B5\u00B6\u00B7'
    '\u00B8\u0105\u015F\u00BB\u013D\u02DD\u013E\u017C'
    '\u0154\u00C1\u00C2\u0102\u00C4\u0139\u0106\u00C7'
    '\u010C\u00C9\u0118\u00CB\u011A\u00CD\u00CE\u010E'
    '\u0110\u0143\u0147\u00D3\u00D4\u0150\u00D6\u00D7'
    '\u0158\u016E\u00DA\u0170\u00DC\u00DD\u0162\u00DF'
    '\u0155\u00E1\u00E2\u0103\u00E4\u013A\u0107\u00E7'
    '\u010D\u00E9\u0119\u00EB\u011B\u00ED\u00EE\u010F'
    '\u0111\u0144\u0148\u00F3\u00F4\u0151\u00F6\u00F7'
    '\u0159\u016F\u00FA\u0171\u00FC\u00FD\u0163\u02D9';

// Bytes 0x80 – 0xFF of code page 1251.
const _cp1251 =
    '\u0402\u0403\u201A\u0453\u201E\u2026\u2020\u2021'
    '\u20AC\u2030\u0409\u2039\u040A\u040C\u040B\u040F'
    '\u0452\u2018\u2019\u201C\u201D\u2022\u2013\u2014'
    '\u0098\u2122\u0459\u203A\u045A\u045C\u045B\u045F'
    '\u00A0\u040E\u045E\u0408\u00A4\u0490\u00A6\u00A7'
    '\u0401\u00A9\u0404\u00AB\u00AC\u00AD\u00AE\u0407'
    '\u00B0\u00B1\u0406\u0456\u0491\u00B5\u00B6\u00B7'
    '\u0451\u2116\u0454\u00BB\u0458\u0405\u0455\u0457'
    '\u0410\u0411\u0412\u0413\u0414\u0415\u0416\u0417'
    '\u0418\u0419\u041A\u041B\u041C\u041D\u041E\u041F'
    '\u0420\u0421\u0422\u0423\u0424\u0425\u0426\u0427'
    '\u0428\u0429\u042A\u042B\u042C\u042D\u042E\u042F'
    '\u0430\u0431\u0432\u0433\u0434\u0435\u0436\u0437'
    '\u0438\u0439\u043A\u043B\u043C\u043D\u043E\u043F'
    '\u0440\u0441\u0442\u0443\u0444\u0445\u0446\u0447'
    '\u0448\u0449\u044A\u044B\u044C\u044D\u044E\u044F';
