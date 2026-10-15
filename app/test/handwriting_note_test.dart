import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/search/handwriting_note.dart';

import 'support/fake_recognizer.dart';

void main() {
  test('a search says why handwriting may be missing (UX_AUDIT R14-2)', () async {
    final none = AppServices.create(AppDatabase.inMemory());
    addTearDown(none.dispose);
    expect(handwritingSearchNote(none.recognition), contains('Android'));

    final here = AppServices.create(AppDatabase.inMemory(), recognizer: FakeRecognizer());
    addTearDown(here.dispose);
    expect(here.recognition.isSupported, isTrue);
    expect(handwritingSearchNote(here.recognition), isNull);
    await here.recognition.setIndexingEnabled(false);
    expect(handwritingSearchNote(here.recognition), 'Handwriting search is off in Settings');
  });
}
