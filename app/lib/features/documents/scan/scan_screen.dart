import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../../../ui/messages.dart';
import 'scan_controls.dart';
import 'scan_corner_editor.dart';
import 'scan_result_view.dart';
import 'scan_session.dart';
import 'scan_sources.dart';

/// The scan screen: photos of pages in, each page's corners adjusted
/// (with a loupe), turned and cleaned up, pages added, retaken or removed.
/// Pops `true` when the user is done ([doneLabel]), null if they leave
/// (asked first once there are pages).
///
/// Without a camera it opens the file picker at once (and closes again if
/// nothing is picked); with one it starts by offering both.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.session,
    required this.doneLabel,
    this.sources = ScanSources.system,
  });

  final ScanSession session;

  /// The primary action, e.g. "Create notebook" or "Insert".
  final String doneLabel;
  final ScanSources sources;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  ScanSession get _session => widget.session;

  /// Photos being read and searched for pages.
  int _loading = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.sources.hasCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_pick(initial: true)));
    }
  }

  // ---------------------------------------------------------------------------
  // Photos

  /// Lets the user pick photos: new pages, or the current page's
  /// replacement ([replace]). Picking nothing [initial]ly leaves.
  Future<void> _pick({bool replace = false, bool initial = false}) async {
    final List<XFile> files;
    try {
      files = await widget.sources.pickPhotos();
    } on Object catch (e) {
      debugPrint('Photo picker failed: $e');
      if (mounted) showMessage(context, 'Couldn’t open the file picker');
      return;
    }
    if (!mounted) return;
    if (files.isEmpty) {
      if (initial && _session.pages.isEmpty) Navigator.of(context).pop();
      return;
    }
    for (final file in replace ? files.take(1) : files) {
      if (!mounted) return;
      await _load(file, replace: replace);
    }
  }

  /// Takes a photo: a new page, or the current page's replacement.
  Future<void> _camera({bool replace = false}) async {
    final XFile? photo;
    try {
      photo = await widget.sources.takePhoto();
    } on Object catch (e) {
      debugPrint('Camera failed: $e');
      if (mounted) showMessage(context, 'Couldn’t open the camera');
      return;
    }
    if (photo == null || !mounted) return;
    await _load(photo, replace: replace);
  }

  Future<void> _load(XFile file, {required bool replace}) async {
    setState(() => _loading++);
    try {
      final photo = await ScanPhoto.load(await file.readAsBytes());
      if (!mounted) return;
      replace ? _session.replaceCurrent(photo) : _session.add(photo);
    } on Object catch (e) {
      debugPrint('Scan photo ${file.name} failed: $e');
      if (mounted) showMessage(context, 'Couldn’t open “${file.name}” as an image');
    } finally {
      if (mounted) setState(() => _loading--);
    }
  }

  /// Adds pages: from the camera or files (asked where there is a camera).
  Future<void> _add(BuildContext anchor) async {
    if (!widget.sources.hasCamera) return _pick();
    final camera = await showContextMenuAt<bool>(
      anchor,
      items: const [
        MenuRow(value: true, icon: Symbols.photo_camera_sharp, label: 'Take photo'),
        MenuRow(value: false, icon: Symbols.image_sharp, label: 'Choose photos…'),
      ],
    );
    if (camera == null || !mounted) return;
    return camera ? _camera() : _pick();
  }

  // ---------------------------------------------------------------------------
  // Leaving

  Future<void> _close() async {
    if (_session.pages.isNotEmpty) {
      final n = _session.pages.length;
      final discard = await confirmAction(
        context,
        title: n == 1 ? 'Discard this scan?' : 'Discard $n scanned pages?',
        message: 'The photos are not added anywhere',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  void _done() => Navigator.of(context).pop(true);

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) {
      final page = _session.current;
      final count = _session.pages.length;
      final busy = _loading > 0;
      return PopScope(
        canPop: count == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_close());
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_close()),
            const SingleActivator(LogicalKeyboardKey.space): _session.toggleResult,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _session.select(_session.index - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _session.select(_session.index + 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () =>
                _session.moveCurrent(-1),
            const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () =>
                _session.moveCurrent(1),
            const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
              if (count > 0 && !busy) _done();
            },
          },
          child: Focus(autofocus: true, child: _scaffold(context, page, count, busy)),
        ),
      );
    },
  );

  Widget _scaffold(BuildContext context, ScanPageDraft? page, int count, bool busy) => Scaffold(
    appBar: _appBar(context, count, busy),
    body: Column(
      children: [
        SizedBox(
          height: Hairline.rule,
          child: busy ? const LinearProgressIndicator(minHeight: Hairline.rule) : null,
        ),
        Expanded(
          child: ColoredBox(
            color: Surfaces.canvasBackdrop(Theme.of(context).brightness),
            child: page == null
                ? ScanEmptyState(
                    busy: busy,
                    onCamera: widget.sources.hasCamera ? _camera : null,
                    onPick: _pick,
                  )
                : AnimatedSwitcher(
                    duration: Motion.fast,
                    child: _session.showsResult
                        ? ScanResultView(
                            key: const ValueKey('result'),
                            image: _session.result,
                            preview: page.preview,
                            aspect: page.aspect,
                            onTap: _session.toggleResult,
                          )
                        : ScanCornerEditor(
                            key: ObjectKey(page),
                            photo: _session.display,
                            photoSize: Size(
                              page.photo.width.toDouble(),
                              page.photo.height.toDouble(),
                            ),
                            quad: page.quad,
                            onChanged: (quad, {required done}) => done
                                ? _session.updatePreview()
                                : _session.setQuad(quad, preview: false),
                          ),
                  ),
          ),
        ),
        if (page != null)
          ScanControls(
            session: _session,
            busy: busy,
            retakeLabel: widget.sources.hasCamera ? 'Retake' : 'Replace…',
            onRetake: () =>
                widget.sources.hasCamera ? _camera(replace: true) : _pick(replace: true),
            onAdd: _add,
          ),
      ],
    ),
  );

  PreferredSizeWidget _appBar(BuildContext context, int count, bool busy) {
    final theme = Theme.of(context);
    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Symbols.close_sharp),
        onPressed: () => unawaited(_close()),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Scan', style: theme.textTheme.titleLarge),
          if (count > 0)
            Text(count == 1 ? '1 page' : '$count pages', style: theme.textTheme.bodySmall),
        ],
      ),
      actions: [
        FilledButton(onPressed: count == 0 || busy ? null : _done, child: Text(widget.doneLabel)),
        const SizedBox(width: Gaps.lg),
      ],
    );
  }
}
