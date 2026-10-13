import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../domain/notebook.dart';
import 'thumbnail_cache.dart';

/// Provides the [ThumbnailCache] to covers; they rebuild as previews arrive.
class ThumbnailScope extends InheritedNotifier<ThumbnailCache> {
  const ThumbnailScope({super.key, required ThumbnailCache cache, required super.child})
    : super(notifier: cache);

  /// The preview of [notebook], or null (no scope, nothing drawn, or not
  /// rendered yet).
  static ui.Image? previewOf(BuildContext context, Notebook notebook) =>
      context.dependOnInheritedWidgetOfExactType<ThumbnailScope>()?.notifier?.imageFor(notebook);

  /// Whether [notebook]'s preview is still to be rendered (false without
  /// a scope). Call after [previewOf], which schedules the render.
  static bool pendingOf(BuildContext context, Notebook notebook) =>
      context.dependOnInheritedWidgetOfExactType<ThumbnailScope>()?.notifier?.isPending(notebook) ??
      false;
}

/// Shows a [ui.Image] owned elsewhere, holding its own clone so the owner
/// may dispose the original at any time.
class PreviewImage extends StatefulWidget {
  const PreviewImage({super.key, required this.image, this.fit = BoxFit.cover});

  final ui.Image image;
  final BoxFit fit;

  @override
  State<PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<PreviewImage> {
  late ui.Image _clone = widget.image.clone();

  @override
  void didUpdateWidget(PreviewImage old) {
    super.didUpdateWidget(old);
    if (!widget.image.isCloneOf(_clone)) {
      _clone.dispose();
      _clone = widget.image.clone();
    }
  }

  @override
  void dispose() {
    _clone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
    image: _clone,
    fit: widget.fit,
    alignment: Alignment.topCenter,
    filterQuality: FilterQuality.medium,
  );
}
