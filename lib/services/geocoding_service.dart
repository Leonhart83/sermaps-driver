import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/stop.dart';

/// Servizio di geocoding tramite Google Geocoding API.
/// Converte un indirizzo testuale in coordinate + componenti (città, provincia).
class GeocodingService {
  static const _base = 'https://maps.googleapis.com/maps/api/geocode/json';

  /// Esegue il geocoding di un singolo indirizzo e aggiorna l'oggetto [stop].
  /// Restituisce true se trovato.
  static Future<bool> geocode(Stop stop) async {
    if (!AppConfig.hasApiKey) {
      throw Exception(
        'Chiave Google Maps mancante. Configurala in local.properties '
        'e/o con --dart-define=MAPS_API_KEY=...',
      );
    }

    final uri = Uri.parse(_base).replace(queryParameters: {
      'address': stop.address,
      'key': AppConfig.googleApiKey,
      'language': 'it',
      'region': 'it',
    });

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Errore di rete durante il geocoding (${resp.statusCode}).');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final status = data['status'] as String?;

    if (status == 'ZERO_RESULTS') {
      return false;
    }
    if (status != 'OK') {
      throw Exception('Geocoding fallito: $status — ${data['error_message'] ?? ''}');
    }

    final results = data['results'] as List<dynamic>;
    if (results.isEmpty) return false;

    final first = results.first as Map<String, dynamic>;
    _fillFromResult(stop, first);
    return true;
  }

  /// Restituisce fino a [limit] candidati per un indirizzo (per gestire i casi
  /// ambigui in cui Google trova più corrispondenze).
  static Future<List<Stop>> geocodeCandidates(
    String address, {
    int limit = 5,
  }) async {
    if (!AppConfig.hasApiKey) {
      throw Exception('Chiave Google Maps mancante.');
    }
    final uri = Uri.parse(_base).replace(queryParameters: {
      'address': address,
      'key': AppConfig.googleApiKey,
      'language': 'it',
      'region': 'it',
    });

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Errore di rete durante il geocoding (${resp.statusCode}).');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    if (status == 'ZERO_RESULTS') return [];
    if (status != 'OK') {
      throw Exception('Geocoding fallito: $status — ${data['error_message'] ?? ''}');
    }
    final results = (data['results'] as List<dynamic>).take(limit);
    return results.map((r) {
      final stop = Stop(address: address);
      _fillFromResult(stop, r as Map<String, dynamic>);
      return stop;
    }).toList();
  }

  /// Popola un [stop] dai dati di un risultato del geocoding.
  static void _fillFromResult(Stop stop, Map<String, dynamic> result) {
    final geometry = result['geometry'] as Map<String, dynamic>;
    final location = geometry['location'] as Map<String, dynamic>;

    stop.lat = (location['lat'] as num).toDouble();
    stop.lng = (location['lng'] as num).toDouble();
    stop.address = result['formatted_address'] as String? ?? stop.address;

    // Estrae i componenti utili.
    final components = result['address_components'] as List<dynamic>;
    for (final c in components) {
      final comp = c as Map<String, dynamic>;
      final types = (comp['types'] as List<dynamic>).cast<String>();
      final longName = comp['long_name'] as String?;
      final shortName = comp['short_name'] as String?;

      if (types.contains('locality')) {
        stop.city = longName;
      } else if (stop.city == null &&
          types.contains('administrative_area_level_3')) {
        stop.city = longName;
      }

      if (types.contains('administrative_area_level_2')) {
        stop.province = longName;
        stop.provinceCode = shortName;
      }
      if (types.contains('administrative_area_level_1')) {
        stop.region = longName;
      }
      if (types.contains('postal_code')) {
        stop.postalCode = longName;
      }
    }
  }
}
