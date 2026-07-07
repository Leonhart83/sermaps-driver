import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/stop.dart';

/// Risultato del calcolo percorso tramite Directions API.
class RouteResult {
  /// Tappe riordinate secondo l'ordine ottimale calcolato da Google.
  final List<Stop> orderedStops;

  /// Distanza totale in metri (escluso l'eventuale ritorno al punto di partenza).
  final int totalDistanceMeters;

  /// Durata totale in secondi (esclusa la tratta di ritorno).
  final int totalDurationSeconds;

  /// Punti del tracciato da disegnare sulla mappa.
  final List<LatLng> polyline;

  /// Distanza (metri) di ogni tratta, allineata a [orderedStops].
  final List<int> legDistances;

  /// Durata (secondi) di ogni tratta, allineata a [orderedStops].
  final List<int> legDurations;

  RouteResult({
    required this.orderedStops,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.polyline,
    required this.legDistances,
    required this.legDurations,
  });

  String get distanceLabel {
    final km = totalDistanceMeters / 1000.0;
    if (km < 1) return '$totalDistanceMeters m';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  String get durationLabel {
    final m = (totalDurationSeconds / 60).round();
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rem = m % 60;
    return rem == 0 ? '$h h' : '$h h $rem min';
  }
}

/// Servizio per il calcolo del percorso reale su strada (Directions API),
/// con ottimizzazione dell'ordine delle tappe lato Google (TSP).
class DirectionsService {
  static const _base = 'https://maps.googleapis.com/maps/api/directions/json';

  /// Calcola il percorso ottimale partendo dalla posizione [startLat]/[startLng],
  /// visitando tutte le [stops]. Per evitare "avanti e indietro" l'ordine viene
  /// ottimizzato da Google quando [optimize] è true. Il percorso torna al punto
  /// di partenza (round trip) ma distanza/tempo riportati escludono il ritorno.
  ///
  /// Lancia un'eccezione con messaggio leggibile in caso di errore.
  static Future<RouteResult> optimizedRoute({
    required double startLat,
    required double startLng,
    required List<Stop> stops,
    bool optimize = true,
  }) async {
    if (!AppConfig.hasApiKey) {
      throw Exception('Chiave Google Maps mancante.');
    }
    final geocoded = stops.where((s) => s.isGeocoded).toList();
    if (geocoded.isEmpty) {
      throw Exception('Nessuna tappa valida da calcolare.');
    }

    final origin = '$startLat,$startLng';
    final prefix = optimize ? 'optimize:true|' : '';
    final waypoints =
        '$prefix${geocoded.map((s) => '${s.lat},${s.lng}').join('|')}';

    final uri = Uri.parse(_base).replace(queryParameters: {
      'origin': origin,
      'destination': origin, // round trip per ottimizzazione completa
      'waypoints': waypoints,
      'mode': 'driving',
      'language': 'it',
      'key': AppConfig.googleApiKey,
    });

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Errore di rete (${resp.statusCode}).');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    if (status != 'OK') {
      throw Exception(
          'Calcolo percorso fallito: $status — ${data['error_message'] ?? ''}');
    }

    final route = (data['routes'] as List).first as Map<String, dynamic>;
    final order = (route['waypoint_order'] as List).cast<int>();
    final legs = (route['legs'] as List).cast<Map<String, dynamic>>();

    // Riordina le tappe secondo l'ordine ottimizzato (se presente).
    final orderedStops =
        order.isEmpty ? geocoded : [for (final i in order) geocoded[i]];

    // Somma distanza/tempo escludendo l'ultima tratta (ritorno all'origine).
    int dist = 0;
    int dur = 0;
    final legDistances = <int>[];
    final legDurations = <int>[];
    final legsToCount = legs.length > 1 ? legs.length - 1 : legs.length;
    for (var i = 0; i < legsToCount; i++) {
      final legDist = (legs[i]['distance']?['value'] as num?)?.toInt() ?? 0;
      final legDur = (legs[i]['duration']?['value'] as num?)?.toInt() ?? 0;
      dist += legDist;
      dur += legDur;
      legDistances.add(legDist);
      legDurations.add(legDur);
      // Assegna la tratta (dalla tappa precedente/partenza) alla tappa di arrivo.
      if (i < orderedStops.length) {
        orderedStops[i].legDistanceMeters = legDist;
        orderedStops[i].legDurationSeconds = legDur;
      }
    }

    // Costruisce la polyline dalle tratte (escluso il ritorno).
    final points = <LatLng>[];
    for (var i = 0; i < legsToCount; i++) {
      final steps = (legs[i]['steps'] as List).cast<Map<String, dynamic>>();
      for (final step in steps) {
        final poly = step['polyline']?['points'] as String?;
        if (poly != null) {
          points.addAll(decodePolyline(poly));
        }
      }
    }

    return RouteResult(
      orderedStops: orderedStops,
      totalDistanceMeters: dist,
      totalDurationSeconds: dur,
      polyline: points,
      legDistances: legDistances,
      legDurations: legDurations,
    );
  }

  /// Decodifica una polyline codificata di Google in una lista di coordinate.
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
