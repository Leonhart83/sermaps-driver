import 'package:flutter_test/flutter_test.dart';
import 'package:sermaps_driver/models/stop.dart';

void main() {
  group('Stop.isOpenAt', () {
    test('senza orari indicati è sempre aperto', () {
      final s = Stop(address: 'A');
      expect(s.isOpenAt(0), isTrue);
      expect(s.isOpenAt(720), isTrue);
      expect(s.hasHours, isFalse);
    });

    test('rispetta apertura e chiusura', () {
      final s = Stop(
        address: 'A',
        openStartMinutes: 9 * 60, // 09:00
        openEndMinutes: 19 * 60, // 19:00
      );
      expect(s.isOpenAt(8 * 60), isFalse); // 08:00 chiuso
      expect(s.isOpenAt(10 * 60), isTrue); // 10:00 aperto
      expect(s.isOpenAt(19 * 60), isFalse); // 19:00 già chiuso
    });

    test('rispetta la pausa pranzo', () {
      final s = Stop(
        address: 'A',
        openStartMinutes: 9 * 60,
        openEndMinutes: 19 * 60,
        lunchStartMinutes: 13 * 60,
        lunchEndMinutes: 15 * 60,
      );
      expect(s.isOpenAt(12 * 60), isTrue); // 12:00 aperto
      expect(s.isOpenAt(14 * 60), isFalse); // 14:00 in pausa
      expect(s.isOpenAt(16 * 60), isTrue); // 16:00 riaperto
    });

    test('isClosedOnArrival usa l\'ETA', () {
      final s = Stop(
        address: 'A',
        openStartMinutes: 9 * 60,
        openEndMinutes: 19 * 60,
        lunchStartMinutes: 13 * 60,
        lunchEndMinutes: 15 * 60,
      )..etaMinutes = 14 * 60;
      expect(s.isClosedOnArrival, isTrue);
      s.etaMinutes = 11 * 60;
      expect(s.isClosedOnArrival, isFalse);
    });

    test('la serializzazione JSON mantiene gli orari', () {
      final s = Stop(
        address: 'A',
        openStartMinutes: 540,
        openEndMinutes: 1140,
        lunchStartMinutes: 780,
        lunchEndMinutes: 900,
      );
      final back = Stop.fromJson(s.toJson());
      expect(back.openStartMinutes, 540);
      expect(back.openEndMinutes, 1140);
      expect(back.lunchStartMinutes, 780);
      expect(back.lunchEndMinutes, 900);
    });
  });
}
