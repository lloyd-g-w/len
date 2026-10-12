import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import '../editor/chrome/chrome_metrics.dart';
import '../editor/editor_session.dart';
import 'notebook_audio.dart';
import 'replay/ink_replay_layer.dart';
import 'replay/replay_target.dart';
import 'ui/audio_bar_button.dart';
import 'ui/playback_bar.dart';

/// What audio adds over the editor's surface (below its chrome): ink
/// replay and the playback bar, both only while a recording is open, and
/// on phones (no room in the top bar) the floating recording controls.
class AudioLayer extends StatefulWidget {
  const AudioLayer({
    super.key,
    required this.audio,
    required this.session,
    required this.chromeInsets,
    this.canvasPaper = PaperColor.white,
  });

  final NotebookAudio audio;
  final EditorSession session;

  /// Screen edges covered by chrome; the playback bar sits above the bottom.
  final EdgeInsets chromeInsets;

  /// Paper colour of an infinite canvas (pages carry their own).
  final PaperColor canvasPaper;

  @override
  State<AudioLayer> createState() => _AudioLayerState();
}

class _AudioLayerState extends State<AudioLayer> {
  late ReplayTarget _target = _targetFor();
  PaperColor? _paper;

  /// Messages shown from the player or the replay (a trim saved, ink not
  /// recorded) appear above the player instead of covering it.
  final _messages = ValueNotifier<double>(0);
  final _barKey = GlobalKey();

  @override
  void dispose() {
    _messages.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box != null && box.hasSize ? box.size.height : 0.0;
    final below = MessageInsets.of(context);
    _messages.value = height == 0
        ? below
        : math.max(below, widget.chromeInsets.bottom + Gaps.md + height);
  }

  ReplayTarget _targetFor() {
    final session = widget.session;
    _paper = widget.canvasPaper;
    final doc = session.doc;
    return doc != null
        ? ReplayTarget.document(doc)
        : ReplayTarget.canvas(session.canvas!, session.canvasViewport!, widget.canvasPaper);
  }

  @override
  void didUpdateWidget(AudioLayer old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session || _paper != widget.canvasPaper) _target = _targetFor();
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.audio.playback;
    final insets = widget.chromeInsets;
    final compact = MediaQuery.sizeOf(context).width < ChromeMetrics.compactWidth;
    return MessageInsets(
      bottom: _messages,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkReplayLayer(audio: widget.audio, target: _target),
          Positioned(
            left: insets.left + Gaps.md,
            right: insets.right + Gaps.md,
            bottom: insets.bottom + Gaps.sm,
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListenableBuilder(
                  listenable: Listenable.merge([playback, widget.audio.recorder]),
                  builder: (context, _) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
                    return Column(
                      key: _barKey,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (compact && widget.audio.recorder.state.isActive)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Gaps.sm),
                            child: Material(
                              elevation: 3,
                              shadowColor: Colors.black26,
                              borderRadius: BorderRadius.circular(Radii.pill),
                              color: Colors.transparent,
                              child: RecordingPill(recorder: widget.audio.recorder),
                            ),
                          ),
                        PlaybackBar(audio: widget.audio),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
