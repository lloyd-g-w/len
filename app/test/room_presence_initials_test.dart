import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/live_ink/room_presence.dart';

/// UX_AUDIT R27-9: devices whose names share an initial still look apart
/// in presence (the bar's plates, the pointers' labels).
void main() {
  test('distinct initials stay one letter', () {
    expect(RoomPresence.initialsOf(['Galaxy Tab S9', 'pixel 8', '  ']), ['G', 'P', '?']);
  });

  test('a shared initial shows the first letters of the first two words', () {
    expect(RoomPresence.initialsOf(['Galaxy Tab S9', 'Galaxy S23', 'Pixel']), ['GT', 'GS', 'P']);
    expect(RoomPresence.initialsOf(['Linux (studio)', 'Linux (laptop)']), ['LS', 'LL']);
    // One word: its first two letters.
    expect(RoomPresence.initialsOf(['Lenovo', 'laptop']), ['LE', 'LA']);
  });

  test('still alike, the initial is numbered', () {
    expect(RoomPresence.initialsOf(['Pixel 7', 'Pixel 7', 'Phone']), ['P', 'P2', 'P3']);
    expect(RoomPresence.initialsOf(['Galaxy S9', 'Galaxy S23']), ['G', 'G2']);
  });
}
