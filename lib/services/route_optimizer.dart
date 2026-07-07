import '../models/stop.dart';
import 'location_service.dart';

/// Criteri di ordinamento disponibili.
enum SortMode {
  /// Ottimizza il percorso: ad ogni passo sceglie la tappa più vicina
  /// (algoritmo nearest-neighbor) partendo dalla posizione attuale.
  optimizeRoute,

  /// Ordina per distanza in linea d'aria dalla posizione attuale.
  byDistance,

  /// Ordina per provincia e poi città (alfabetico).
  byProvinceCity,

  /// Ordina per orario limite di consegna (scadenza più vicina prima).
  byDeadline,
}

extension SortModeLabel on SortMode {
  String get label {
    switch (this) {
      case SortMode.optimizeRoute:
        return 'Ottimizza percorso';
      case SortMode.byDistance:
        return 'Distanza dalla mia posizione';
      case SortMode.byProvinceCity:
        return 'Provincia / Città';
      case SortMode.byDeadline:
        return 'Orario di consegna';
    }
  }
}

class RouteOptimizer {
  /// Ordina le tappe secondo il [mode] indicato.
  /// [startLat]/[startLng] è la posizione di partenza (GPS attuale).
  /// Le tappe senza coordinate vengono messe in fondo, invariate.
  static List<Stop> sort(
    List<Stop> stops, {
    required SortMode mode,
    double? startLat,
    double? startLng,
    int? nowMinutes,
  }) {
    final geocoded = stops.where((s) => s.isGeocoded).toList();
    final notGeocoded = stops.where((s) => !s.isGeocoded).toList();

    switch (mode) {
      case SortMode.byProvinceCity:
        geocoded.sort((a, b) {
          final pa = (a.province ?? a.provinceCode ?? '').toLowerCase();
          final pb = (b.province ?? b.provinceCode ?? '').toLowerCase();
          final byProv = pa.compareTo(pb);
          if (byProv != 0) return byProv;
          final ca = (a.city ?? '').toLowerCase();
          final cb = (b.city ?? '').toLowerCase();
          return ca.compareTo(cb);
        });
        break;

      case SortMode.byDistance:
        if (startLat != null && startLng != null) {
          geocoded.sort((a, b) {
            final da = LocationService.distanceMeters(
                startLat, startLng, a.lat!, a.lng!);
            final db = LocationService.distanceMeters(
                startLat, startLng, b.lat!, b.lng!);
            return da.compareTo(db);
          });
        }
        break;

      case SortMode.byDeadline:
        // Scadenza più vicina prima; le tappe senza orario vanno in fondo.
        geocoded.sort((a, b) {
          final da = a.deadlineMinutes;
          final db = b.deadlineMinutes;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
        break;

      case SortMode.optimizeRoute:
        // Rispetta i vincoli di posizione: tappe "prima" all'inizio (nel loro
        // ordine), tappe "ultima" alla fine, il resto nearest-neighbor.
        final pinnedFirst =
            geocoded.where((s) => s.pin == StopPin.first).toList();
        final pinnedLast =
            geocoded.where((s) => s.pin == StopPin.last).toList();
        final middle =
            geocoded.where((s) => s.pin == StopPin.none).toList();
        // Il nearest-neighbor del centro parte dall'ultima tappa "prima"
        // (se presente), altrimenti dalla posizione attuale.
        final fromLat = pinnedFirst.isNotEmpty ? pinnedFirst.last.lat : startLat;
        final fromLng = pinnedFirst.isNotEmpty ? pinnedFirst.last.lng : startLng;
        // Se è nota l'ora e almeno una tappa ha orari (apertura/pausa), usa il
        // nearest-neighbor che tiene conto degli orari (evita di arrivare
        // quando l'attività è chiusa). Altrimenti quello classico spaziale.
        final useTimeAware =
            nowMinutes != null && middle.any((s) => s.hasHours || s.hasLunchBreak);
        final orderedMiddle = useTimeAware
            ? _nearestNeighborTimeAware(middle, fromLat, fromLng, nowMinutes)
            : _nearestNeighbor(middle, fromLat, fromLng);
        return [
          ...pinnedFirst,
          ...orderedMiddle,
          ...pinnedLast,
          ...notGeocoded,
        ];
    }

    return [...geocoded, ...notGeocoded];
  }

  /// Algoritmo nearest-neighbor: partendo dalla posizione attuale, sceglie
  /// ripetutamente la tappa non visitata più vicina all'ultima scelta.
  static List<Stop> _nearestNeighbor(
    List<Stop> stops,
    double? startLat,
    double? startLng,
  ) {
    if (stops.isEmpty) return [];

    final remaining = List<Stop>.from(stops);
    final ordered = <Stop>[];

    double curLat;
    double curLng;

    if (startLat != null && startLng != null) {
      curLat = startLat;
      curLng = startLng;
    } else {
      // Senza posizione di partenza si parte dalla prima tappa.
      final first = remaining.removeAt(0);
      ordered.add(first);
      curLat = first.lat!;
      curLng = first.lng!;
    }

    while (remaining.isNotEmpty) {
      var bestIndex = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final s = remaining[i];
        final d =
            LocationService.distanceMeters(curLat, curLng, s.lat!, s.lng!);
        if (d < bestDist) {
          bestDist = d;
          bestIndex = i;
        }
      }
      final next = remaining.removeAt(bestIndex);
      ordered.add(next);
      curLat = next.lat!;
      curLng = next.lng!;
    }

    return ordered;
  }

  /// Velocità media stimata (km/h) per convertire le distanze in tempi.
  static const double _avgSpeedKmh = 35;

  /// Tempo di servizio stimato per ogni tappa (minuti).
  static const int _serviceMinutes = 5;

  /// True se la tappa risulta chiusa (orari/pausa) all'orario [minutes].
  static bool _isClosedAt(Stop s, double minutes) {
    return !s.isOpenAt(minutes.round());
  }

  /// Nearest-neighbor consapevole degli orari: a ogni passo preferisce la
  /// tappa aperta più vicina; se tutte le rimanenti sarebbero chiuse
  /// all'arrivo, sceglie comunque la più vicina. Stima i tempi con la
  /// distanza in linea d'aria e una velocità media, poi le distanze reali
  /// vengono ricalcolate dalla Directions API.
  static List<Stop> _nearestNeighborTimeAware(
    List<Stop> stops,
    double? startLat,
    double? startLng,
    int nowMinutes,
  ) {
    if (stops.isEmpty) return [];

    final remaining = List<Stop>.from(stops);
    final ordered = <Stop>[];
    double clock = nowMinutes.toDouble();
    double curLat;
    double curLng;

    if (startLat != null && startLng != null) {
      curLat = startLat;
      curLng = startLng;
    } else {
      final first = remaining.removeAt(0);
      ordered.add(first);
      curLat = first.lat!;
      curLng = first.lng!;
      clock += _serviceMinutes;
    }

    while (remaining.isNotEmpty) {
      var bestAny = 0;
      var bestAnyDist = double.infinity;
      int? bestOpen;
      var bestOpenDist = double.infinity;

      for (var i = 0; i < remaining.length; i++) {
        final s = remaining[i];
        final d =
            LocationService.distanceMeters(curLat, curLng, s.lat!, s.lng!);
        if (d < bestAnyDist) {
          bestAnyDist = d;
          bestAny = i;
        }
        final travelMin = (d / 1000.0) / _avgSpeedKmh * 60.0;
        final arrival = clock + travelMin;
        if (!_isClosedAt(s, arrival) && d < bestOpenDist) {
          bestOpenDist = d;
          bestOpen = i;
        }
      }

      final idx = bestOpen ?? bestAny;
      final next = remaining.removeAt(idx);
      final d =
          LocationService.distanceMeters(curLat, curLng, next.lat!, next.lng!);
      final travelMin = (d / 1000.0) / _avgSpeedKmh * 60.0;
      clock += travelMin + _serviceMinutes;
      ordered.add(next);
      curLat = next.lat!;
      curLng = next.lng!;
    }

    return ordered;
  }
}
