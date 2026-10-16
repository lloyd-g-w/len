import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Tells screen readers [message] now: for changes a sighted user sees
/// happen (a control swapping for others, an icon turning) that move no
/// focus and show no text of their own.
void announce(BuildContext context, String message) =>
    SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context));
