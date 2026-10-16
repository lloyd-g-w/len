import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where an editor was looking, remembered per tab while it is not shown
/// and per notebook across launches ([encode] / [decode]).
@immutable
class EditorViewState {
  const EditorViewState({
    required this.scale,
    required this.offset,
    this.page = 0,
    this.size,
    this.fit,
    this.savedAt,
  });

  /// Page [page] framed as the editor frames a page it goes to (a size
  /// no viewport has, so it is never restored as a zoom and pan).
  const EditorViewState.page(this.page, {this.fit})
    : scale = 1,
      offset = Offset.zero,
      size = Size.zero,
      savedAt = null;

  /// Viewport zoom and pan (`screen = world * scale + offset`).
  final double scale;
  final Offset offset;

  /// The current page of a paged notebook.
  final int page;

  /// The viewport's size when the view was saved: a different size (a
  /// rotated tablet, a resized window) re-fits instead of restoring.
  final Size? size;

  /// How a paged notebook fits pages (`PageFit.name`), if chosen.
  final String? fit;

  /// When this device kept the view (ms since epoch), if known: ink other
  /// devices wrote later decides where the notebook opens (R16-4).
  final int? savedAt;

  /// This view, kept at [at].
  EditorViewState stamped(int at) =>
      EditorViewState(scale: scale, offset: offset, page: page, size: size, fit: fit, savedAt: at);

  /// Whether this view was saved at [other] size (or the size is unknown).
  bool fitsSize(Size other) {
    final s = size;
    return s == null || ((s.width - other.width).abs() < 1 && (s.height - other.height).abs() < 1);
  }

  /// A compact text form for the settings store.
  String encode() => [
    scale,
    offset.dx,
    offset.dy,
    page,
    size?.width ?? '',
    size?.height ?? '',
    fit ?? '',
    savedAt ?? '',
  ].join(',');

  /// Parses [encode]'s output; null if [text] is missing or malformed.
  static EditorViewState? decode(String? text) {
    final parts = text?.split(',');
    if (parts == null || parts.length < 4) return null;
    final scale = double.tryParse(parts[0]);
    final dx = double.tryParse(parts[1]), dy = double.tryParse(parts[2]);
    final page = int.tryParse(parts[3]);
    if (scale == null || !scale.isFinite || scale <= 0 || dx == null || dy == null) return null;
    final w = parts.length > 5 ? double.tryParse(parts[4]) : null;
    final h = parts.length > 5 ? double.tryParse(parts[5]) : null;
    final fit = parts.length > 6 && parts[6].isNotEmpty ? parts[6] : null;
    final savedAt = parts.length > 7 ? int.tryParse(parts[7]) : null;
    return EditorViewState(
      scale: scale,
      offset: Offset(dx, dy),
      page: page ?? 0,
      size: w == null || h == null ? null : Size(w, h),
      fit: fit,
      savedAt: savedAt,
    );
  }
}
