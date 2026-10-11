import 'dart:ui';

import 'surface_element.dart';

/// Where a link element leads: a page (of this or another notebook) or a
/// web address. Stored in a `link` element's `data.target`.
sealed class LinkTarget {
  const LinkTarget();

  Map<String, Object?> toJson();

  /// Parses [json]; null if it is not a valid target.
  static LinkTarget? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final page = json['page'], notebook = json['notebook'], url = json['url'];
    if (page is String && notebook is String && page.isNotEmpty && notebook.isNotEmpty) {
      return PageLinkTarget(notebookId: notebook, pageId: page);
    }
    if (url is String) return UrlLinkTarget.parse(url);
    return null;
  }
}

/// A page of a paged notebook; found by id, so reordering pages never
/// breaks the link.
final class PageLinkTarget extends LinkTarget {
  const PageLinkTarget({required this.notebookId, required this.pageId});

  final String notebookId;
  final String pageId;

  @override
  Map<String, Object?> toJson() => {'notebook': notebookId, 'page': pageId};

  @override
  bool operator ==(Object other) =>
      other is PageLinkTarget && other.notebookId == notebookId && other.pageId == pageId;

  @override
  int get hashCode => Object.hash(notebookId, pageId);
}

/// A web (or mail) address.
final class UrlLinkTarget extends LinkTarget {
  const UrlLinkTarget(this.uri);

  final Uri uri;

  /// Schemes a link may open.
  static const schemes = {'http', 'https', 'mailto'};

  /// Parses what the user typed or a stored address: `example.com` becomes
  /// `https://example.com`; null unless it is an http(s) or mailto address.
  static UrlLinkTarget? parse(String text) {
    var t = text.trim();
    if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
    if (!t.contains(':')) t = t.contains('@') ? 'mailto:$t' : 'https://$t';
    final uri = Uri.tryParse(t);
    if (uri == null || !schemes.contains(uri.scheme.toLowerCase())) return null;
    if (uri.scheme != 'mailto' && uri.host.isEmpty) return null;
    return UrlLinkTarget(uri);
  }

  @override
  Map<String, Object?> toJson() => {'url': uri.toString()};

  @override
  bool operator ==(Object other) => other is UrlLinkTarget && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

/// Link elements: an invisible region of a surface (drawn by the editor
/// with a subtle affordance, never in exports or thumbnails) that leads to
/// a [LinkTarget]. As elements they move, copy, undo and sync with the
/// content they were made from.
abstract final class LinkElements {
  /// Margin around linked content, in world units.
  static const double padding = 4;

  /// A link over [rect] of surface [surfaceId]. Links sit beneath the ink
  /// (negative [z]), so tapping linked ink with the lasso selects the ink.
  static SurfaceElement create({
    required String id,
    required String surfaceId,
    required Rect rect,
    required LinkTarget target,
    required int createdAt,
    required double z,
  }) => SurfaceElement(
    id: id,
    surfaceId: surfaceId,
    type: ElementType.link.name,
    rect: rect,
    z: z,
    createdAt: createdAt,
    data: {'target': target.toJson()},
  );

  /// The target of link element [element]; null for other elements and
  /// links with an invalid target.
  static LinkTarget? targetOf(SurfaceElement element) =>
      element.knownType == ElementType.link ? LinkTarget.fromJson(element.data['target']) : null;

  static bool isLink(SurfaceElement element) => element.knownType == ElementType.link;
}
