import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import '../editor/editor_session.dart';
import 'notebook_audio.dart';
import 'replay/ink_replay_layer.dart';
import 'replay/replay_target.dart';
import 'ui/audio_bar_button.dart';
import 'ui/playback_bar.dart';

/// What audio adds over the editor's surface (below its chrome): ink
/// replay and the player, both only while a recording is open, and on
/// phones (no room in the top bar) the recording controls. Player and
/// controls share one docked strip along the bottom: flat Board with a
/// hairline on the edge facing the page, like the bars (DESIGN §3).
class AudioLayer extends StatefulWidget {
  const AudioLayer({
    super.key,
    required this.audio,
    required this.session,
    required this.chromeInsets,
    required this.compactBar,
    this.canvasPaper = PaperColor.white,
  });

  final NotebookAudio audio;
  final EditorSession session;

  /// Screen edges covered by chrome; the playback bar sits above the bottom.
  final EdgeInsets chromeInsets;

  /// The top bar is the phone's, without the audio button (phones, short
  /// windows): the recording controls dock at the bottom instead.
  final bool compactBar;

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
    _messages.value = height == 0 ? below : math.max(below, widget.chromeInsets.bottom + height);
    widget.audio.stripHeight.value = height;
    // The document's end makes room too, so "Add page" isn't under them.
    widget.session.doc?.setEndRoom(height == 0 ? 0 : height + Gaps.sm);
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
    final compact = widget.compactBar;
    return MessageInsets(
      bottom: _messages,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkReplayLayer(audio: widget.audio, target: _target),
          Positioned(
            left: insets.left,
            right: insets.right,
            bottom: insets.bottom,
            child: ListenableBuilder(
              listenable: Listenable.merge([playback, widget.audio.recorder]),
              builder: (context, _) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
                final recording = compact && widget.audio.recorder.state.isActive;
                final playing = playback.recording != null;
                if (!recording && !playing) return SizedBox(key: _barKey);
                return _AudioStrip(
                  key: _barKey,
                  children: [
                    if (recording)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: RecordingControls(recorder: widget.audio.recorder),
                      ),
                    if (recording && playing) const Divider(height: Hairline.width),
                    if (playing) PlaybackBar(audio: widget.audio),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The docked audio strip: Board, a hairline on top, its content at most
/// 560 dp wide in the middle.
class _AudioStrip extends StatelessWidget {
  const _AudioStrip({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Surfaces.chrome(scheme),
        border: Border(top: Surfaces.chromeEdge(scheme)),
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
