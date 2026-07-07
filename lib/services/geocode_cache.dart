import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/stop.dart';

/// Cache locale degli indirizzi già risolti (geocoding).
///
/// Salva le coordinate e i componenti di ogni indirizzo cercato, così da:
/// - evitare nuove chiamate (a pagamento) alla Geocoding API;
/// - funzionare offline quando si reinserisce un indirizzo già noto.
class GeocodeCache {
  static const _key = 'geocode_cache_v1';
  static Map<String, Map<String, dynamic>>? _cache;

  /// Normalizza un indirizzo per usarlo come chiave (minuscolo, spazi compatti).
  static String _norm(String address) =>
      address.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static Future<Map<String, Map<String, dynamic>>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _cache = {};
      return _cache!;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _cache = map.map(
        (k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()),
      );
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  /// Cerca un indirizzo in cache e, se presente, popola [stop] (mantenendo
  /// il suo id). Restituisce true se trovato.
  static Future<bool> fill(Stop stop) async {
    final cache = await _load();
    final data = cache[_norm(stop.address)];
    if (data == null) return false;
    stop.lat = (data['lat'] as num?)?.toDouble();
    stop.lng = (data['lng'] as num?)?.toDouble();
    stop.address = data['address'] as String? ?? stop.address;
    stop.city = data['city'] as String?;
    stop.province = data['province'] as String?;
    stop.provinceCode = data['provinceCode'] as String?;
    stop.region = data['region'] as String?;
    stop.postalCode = data['postalCode'] as String?;
    return stop.isGeocoded;
  }

  /// Memorizza un indirizzo risolto in cache.
  static Future<void> store(String query, Stop stop) async {
    if (!stop.isGeocoded) return;
    final cache = await _load();
    cache[_norm(query)] = {
      'lat': stop.lat,
      'lng': stop.lng,
      'address': stop.address,
      'city': stop.city,
      'province': stop.province,
      'provinceCode': stop.provinceCode,
      'region': stop.region,
      'postalCode': stop.postalCode,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(cache));
  }

  /// Svuota la cache degli indirizzi.
  static Future<void> clear() async {
    _cache = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
