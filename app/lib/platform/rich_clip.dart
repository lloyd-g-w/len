/// Formatted text on the system clipboard as other apps put it there: HTML
/// and / or RTF (null where absent or unreadable).
typedef RichClip = ({String? html, String? rtf});

/// A clipboard without formatted text.
const RichClip noRichClip = (html: null, rtf: null);
