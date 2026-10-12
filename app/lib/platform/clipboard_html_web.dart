import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:web/web.dart' as web;

/// The last browser paste event: its plain text and HTML (null for a
/// paste as plain text, Ctrl+Shift+V) and when it happened.
({String plain, String? html, int at})? _last;
bool _plainNext = false;
bool _watching = false;

/// How long a paste event's HTML stays claimable.
const _freshMs = 1500;

/// Starts watching paste events (capturing, so the hidden text field
/// Flutter edits through reports them too). Idempotent.
void watchClipboardPastes() {
  if (_watching) return;
  _watching = true;
  web.document.addEventListener(
    'keydown',
    ((web.KeyboardEvent e) {
      _plainNext = e.shiftKey && (e.ctrlKey || e.metaKey) && e.key.toLowerCase() == 'v';
    }).toJS,
    true.toJS,
  );
  web.document.addEventListener(
    'paste',
    ((web.ClipboardEvent e) {
      final data = e.clipboardData;
      final html = data?.getData('text/html') ?? '';
      _last = (
        plain: data?.getData('text/plain') ?? '',
        html: html.isEmpty || _plainNext ? null : html,
        at: DateTime.now().millisecondsSinceEpoch,
      );
      _plainNext = false;
    }).toJS,
    true.toJS,
  );
}

String _norm(String s) => s.replaceAll('\r\n', '\n').trim();

/// Takes the last paste event if it is recent (and, with [plain], inserted
/// that text).
({String plain, String? html, int at})? _take([String? plain]) {
  final last = _last;
  if (last == null || DateTime.now().millisecondsSinceEpoch - last.at > _freshMs) return null;
  if (plain != null && _norm(last.plain) != _norm(plain)) return null;
  _last = null;
  return last;
}

/// The HTML of the browser paste that just inserted [plain] into a text
/// field, or null.
String? htmlPastedAs(String plain) => _take(plain)?.html;

/// The clipboard's HTML: from a paste event that just happened, else the
/// async Clipboard API (the browser may ask for permission).
Future<String?> readClipboardHtml() async {
  final event = _take();
  if (event != null) return event.html;
  try {
    final html = await Pasteboard.html;
    return html == null || html.isEmpty ? null : html;
  } catch (e) {
    debugPrint('Clipboard HTML unavailable: $e');
    return null;
  }
}
