import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// What the camera was opened for: kept while the camera app is in front,
/// so a photo coming back after Android killed Len (see `Camera`) still
/// goes where it was meant to.
@immutable
sealed class CameraPurpose {
  const CameraPurpose();

  /// The purpose stored as [encode]d; null if unreadable.
  static CameraPurpose? decode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return null;
      return switch (json) {
        {'kind': 'scan', 'notebook': null} => const ScanNewNotebook(),
        {'kind': 'scan', 'notebook': final String notebook, 'after': final String? after} =>
          ScanIntoNotebook(notebook, afterPageId: after),
        {
          'kind': 'photo',
          'notebook': final String notebook,
          'surface': final String surface,
          'x': final num x,
          'y': final num y,
        } =>
          PhotoOnSurface(notebook, surfaceId: surface, at: Offset(x.toDouble(), y.toDouble())),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  /// This purpose as a string for the settings.
  String encode() => jsonEncode(switch (this) {
    ScanNewNotebook() => {'kind': 'scan', 'notebook': null},
    ScanIntoNotebook(:final notebookId, :final afterPageId) => {
      'kind': 'scan',
      'notebook': notebookId,
      'after': afterPageId,
    },
    PhotoOnSurface(:final notebookId, :final surfaceId, :final at) => {
      'kind': 'photo',
      'notebook': notebookId,
      'surface': surfaceId,
      'x': at.dx,
      'y': at.dy,
    },
  });
}

/// A page of a scan into a new notebook (from the library).
final class ScanNewNotebook extends CameraPurpose {
  const ScanNewNotebook();

  @override
  bool operator ==(Object other) => other is ScanNewNotebook;

  @override
  int get hashCode => (ScanNewNotebook).hashCode;
}

/// A page of a scan inserted into paged notebook [notebookId] after page
/// [afterPageId] (at the end if null).
final class ScanIntoNotebook extends CameraPurpose {
  const ScanIntoNotebook(this.notebookId, {this.afterPageId});

  final String notebookId;
  final String? afterPageId;

  @override
  bool operator ==(Object other) =>
      other is ScanIntoNotebook &&
      other.notebookId == notebookId &&
      other.afterPageId == afterPageId;

  @override
  int get hashCode => Object.hash(notebookId, afterPageId);
}

/// A photo inserted (Insert → Take photo) on surface [surfaceId] — a page,
/// or the canvas (the notebook's id) — of notebook [notebookId], centred
/// on [at] in the surface's coordinates.
final class PhotoOnSurface extends CameraPurpose {
  const PhotoOnSurface(this.notebookId, {required this.surfaceId, required this.at});

  final String notebookId;
  final String surfaceId;
  final Offset at;

  @override
  bool operator ==(Object other) =>
      other is PhotoOnSurface &&
      other.notebookId == notebookId &&
      other.surfaceId == surfaceId &&
      other.at == at;

  @override
  int get hashCode => Object.hash(notebookId, surfaceId, at);
}
