import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the screen-reader custom action [action] on the semantics node of
/// the row showing [label], as TalkBack's actions menu would, after checking
/// that the row's one node (named [label], no unlabelled child) offers it.
Future<void> performCustomAction(WidgetTester tester, String label, String action) async {
  final node = tester.getSemantics(find.text(label).last);
  final data = node.getSemanticsData();
  final id = CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: action));
  expect(data.label, label);
  expect(data.customSemanticsActionIds, contains(id), reason: '"$label" offers "$action"');
  expect(data.hasAction(SemanticsAction.tap), isTrue, reason: 'the row itself, a button');
  node.owner!.performAction(node.id, SemanticsAction.customAction, id);
  await tester.pumpAndSettle();
}
