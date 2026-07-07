import 'package:flutter_test/flutter_test.dart';
import 'package:sermaps_driver/models/stop.dart';
import 'package:sermaps_driver/services/route_optimizer.dart';

void main() {
  group('RouteOptimizer.sort', () {
    test('senza orari: ordina per vicinanza (nearest-neighbor)', () {
      final near = Stop(address: 'vicina', lat: 45.001, lng: 7.0);
      final far = Stop(address: 'lontana', lat: 45.004, lng: 7.0);
      final result = RouteOptimizer.sort(
        [far, near],
        mode: SortMode.optimizeRoute,
        startLat: 45.0,
        startLng: 7.0,
      );
      expect(result.first.address, 'vicina');
      expect(result.last.address, 'lontana');
    });

    test('con orari: rimanda la tappa chiusa all\'arrivo', () {
      // La tappa più vicina è chiusa (pausa 13-15), l'altra è aperta.
      final vicinaChiusa = Stop(
        address: 'vicina-chiusa',
        lat: 45.001,
        lng: 7.0,
        openStartMinutes: 9 * 60,
        openEndMinutes: 19 * 60,
        lunchStartMinutes: 13 * 60,
        lunchEndMinutes: 15 * 60,
      );
      final lontanaAperta = Stop(
        address: 'lontana-aperta',
        lat: 45.004,
        lng: 7.0,
        openStartMinutes: 9 * 60,
        openEndMinutes: 19 * 60,
      );
      final result = RouteOptimizer.sort(
        [vicinaChiusa, lontanaAperta],
        mode: SortMode.optimizeRoute,
        startLat: 45.0,
        startLng: 7.0,
        nowMinutes: 14 * 60, // 14:00: la vicina è in pausa
      );
      // La tappa aperta viene prima, quella chiusa è rimandata.
      expect(result.first.address, 'lontana-aperta');
      expect(result.last.address, 'vicina-chiusa');
    });

    test('rispetta i vincoli di posizione (prima/ultima)', () {
      final first = Stop(
        address: 'prima',
        lat: 45.004,
        lng: 7.0,
        pin: StopPin.first,
      );
      final middle = Stop(address: 'centro', lat: 45.001, lng: 7.0);
      final last = Stop(
        address: 'ultima',
        lat: 45.0005,
        lng: 7.0,
        pin: StopPin.last,
      );
      final result = RouteOptimizer.sort(
        [middle, last, first],
        mode: SortMode.optimizeRoute,
        startLat: 45.0,
        startLng: 7.0,
      );
      expect(result.first.address, 'prima');
      expect(result.last.address, 'ultima');
    });
  });
}
