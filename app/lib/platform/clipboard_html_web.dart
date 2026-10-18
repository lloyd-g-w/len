import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:web/web.dart' as web;

import 'rich_clip.dart';

/// The last browser paste event: its plain text, HTML and RTF (null for
/// a paste as plain text, Ctrl+Shift+V) and when it happened.
({String plain, RichClip rich, int at})? _last;
bool _plainNext = false;
bool _watching = false;

/// How long a paste event's formatted text stays claimable.
const _freshMs = 1500;

/// Starts watching paste events, and copy and cut events for
/// [claimFieldCopies] (capturing, so the hidden text field Flutter edits
/// through reports them too). Idempotent.
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
      String? rich(String type) {
        final text = _plainNext ? '' : data?.getData(type) ?? '';
        return text.isEmpty ? null : text;
      }

      // (Chromium passes RTF from native apps, e.g. WordPad on Windows.)
      _last = (
        plain: data?.getData('text/plain') ?? '',
        rich: (html: rich('text/html'), rtf: rich('text/rtf')),
        at: DateTime.now().millisecondsSinceEpoch,
      );
      _plainNext = false;
    }).toJS,
    true.toJS,
  );
  for (final cut in [false, true]) {
    web.document.addEventListener(
      cut ? 'cut' : 'copy',
      ((web.ClipboardEvent e) => _onCopy(e, cut: cut)).toJS,
      true.toJS,
    );
  }
}

Object? _copyOwner;
({String plain, String html})? Function(bool cut)? _copy;

/// Answers the browser's copy and cut events with [copy] while [owner]
/// holds them: a text field whose text (with layout inserts) differs from
/// what it copies. [copy] returns null to leave an event to the browser.
void claimFieldCopies(Object owner, ({String plain, String html})? Function(bool cut) copy) {
  watchClipboardPastes();
  _copyOwner = owner;
  _copy = copy;
}

/// Stops [owner]'s [claimFieldCopies] (if it still holds them).
void releaseFieldCopies(Object owner) {
  if (!identical(_copyOwner, owner)) return;
  _copyOwner = null;
  _copy = null;
}

void _onCopy(web.ClipboardEvent e, {required bool cut}) {
  final data = e.clipboardData;
  final out = data == null ? null : _copy?.call(cut);
  if (out == null) return;
  data!
    ..setData('text/plain', out.plain)
    ..setData('text/html', out.html);
  e.preventDefault();
}

String _norm(String s) => s.replaceAll('\r\n', '\n').trim();

/// Takes the last paste event if it is recent (and, with [plain], inserted
/// that text).
({String plain, RichClip rich, int at})? _take([String? plain]) {
  final last = _last;
  if (last == null || DateTime.now().millisecondsSinceEpoch - last.at > _freshMs) return null;
  if (plain != null && _norm(last.plain) != _norm(plain)) return null;
  _last = null;
  return last;
}

/// The formatted text of the browser paste that just inserted [plain]
/// into a text field, or null.
RichClip? richPastedAs(String plain) => _take(plain)?.rich;

/// The clipboard's formatted text: from a paste event that just happened
/// (HTML and RTF), else the async Clipboard API's HTML (the browser may ask
/// for permission; it offers no RTF).
Future<RichClip> readClipboardRich() async {
  final event = _take();
  if (event != null) return event.rich;
  try {
    final html = await Pasteboard.html;
    return (html: html == null || html.isEmpty ? null : html, rtf: null);
  } catch (e) {
    debugPrint('Clipboard HTML unavailable: $e');
    return noRichClip;
  }
}
