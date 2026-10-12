/// The tools selectable in the editor toolbar.
enum EditorTool {
  pen,
  highlighter,
  eraser,
  lasso,
  shape,
  text,
  laser;

  /// Whether the tool draws ink with the active ink's quick colour and width.
  bool get usesInk => this == pen || this == highlighter || this == shape;
}
