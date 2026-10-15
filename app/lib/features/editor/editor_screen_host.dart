part of 'editor_screen.dart';

/// Hosts the editor under a [MessageInsets], so every message shown from
/// the editor (its own state included) clears the bottom chrome.
class _EditorHostState extends State<EditorScreen> {
  final _messageInset = ValueNotifier<double>(0);

  @override
  void dispose() {
    _messageInset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MessageInsets(
    bottom: _messageInset,
    child: _EditorView(
      notebook: widget.notebook,
      messageInset: _messageInset,
      split: widget.split,
      secondPane: widget.secondPane,
    ),
  );
}

class _EditorView extends StatefulWidget {
  const _EditorView({
    required this.notebook,
    required this.messageInset,
    this.split,
    this.secondPane = false,
  });

  final Notebook notebook;
  final SplitController? split;
  final bool secondPane;

  /// Updated with the room the bottom chrome takes.
  final ValueNotifier<double> messageInset;

  @override
  State<_EditorView> createState() => _EditorScreenState();
}
