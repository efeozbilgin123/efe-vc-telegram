import 'package:flutter_test/flutter_test.dart';
import 'package:portal_voice/proximity.dart';

void main() {
  final t = DateTime.utc(2026, 10, 19);
  test('nearby, far away, and different dimensions', () {
    final a = VoicePosition(0, 64, 0, 'minecraft:overworld', t);
    final b = VoicePosition(3, 68, 0, 'minecraft:overworld', t);
    final far = VoicePosition(100, 64, 0, 'minecraft:overworld', t);
    final nether = VoicePosition(0, 64, 0, 'minecraft:the_nether', t);
    expect(shouldHear(a, b, radius: 6, now: t), isTrue);
    expect(shouldHear(a, far, radius: 32, now: t), isFalse);
    expect(shouldHear(a, nether, radius: 32, now: t), isFalse);
  });

  test('stale positions cannot speak', () {
    final old = VoicePosition(0, 0, 0, 'world', DateTime.utc(2026, 10, 18));
    final current = VoicePosition(0, 0, 0, 'world', t);
    expect(shouldHear(old, current, radius: 32, now: t), isFalse);
  });

  test('malformed/huge/NaN positions rejected', () {
    expect(VoicePosition.fromJson({'x': 0, 'y': 0, 'z': double.nan,
      'dimension': 'world'}, now: t), isNull);
    expect(VoicePosition.fromJson({'x': 30000001, 'y': 0, 'z': 0,
      'dimension': 'world'}, now: t), isNull);
  });
}
