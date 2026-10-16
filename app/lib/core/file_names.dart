import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;

/// A file name from a notebook title: characters file systems refuse
/// become spaces, runs of spaces one ("Physics: week 3/4" → "Physics week
/// 3 4", R22-5), no trailing dots (Windows drops them), at most
/// [maxFileNameBase] characters and [_maxBaseBytes] bytes of UTF-8 (whole
/// characters), and never a Windows device name ("CON", "NUL.txt"…: such a
/// file is the device), which gets a "_". [fallback] names a title with
/// nothing left.
String safeFileName(String title, {String fallback = 'Notebook'}) {
  var cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final kept = StringBuffer();
  var count = 0, bytes = 0;
  for (final c in cleaned.characters) {
    bytes += utf8.encode(c).length;
    if (++count > maxFileNameBase || bytes > _maxBaseBytes) break;
    kept.write(c);
  }
  cleaned = kept.toString().replaceFirst(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty) return fallback;
  final device = cleaned.split('.').first.trimRight();
  return _windowsDevice.hasMatch(device)
      ? '${device}_${cleaned.substring(device.length)}'
      : cleaned;
}

/// Names Windows keeps for devices, whatever the extension.
final _windowsDevice = RegExp(r'^(CON|PRN|AUX|NUL|COM[0-9¹²³]|LPT[0-9¹²³])$', caseSensitive: false);

/// Longest notebook title kept in a file name, leaving room for a page
/// range and the extension within file systems' 255 bytes.
const int maxFileNameBase = 100;

/// At most this many bytes of UTF-8 of a title go into a file name.
const int _maxBaseBytes = 180;

/// [name] if no name in [taken] differs from it only by case (Windows and
/// macOS file systems, and the folders a ZIP unpacks into there, don't
/// tell them apart), else with " (2)", " (3)"… before its extension; adds
/// it to [taken] (names in lower case).
String uniqueFileName(String name, Set<String> taken) {
  final dot = name.lastIndexOf('.');
  var candidate = name;
  for (var n = 2; !taken.add(candidate.toLowerCase()); n++) {
    candidate = dot <= 0 ? '$name ($n)' : '${name.substring(0, dot)} ($n)${name.substring(dot)}';
  }
  return candidate;
}
