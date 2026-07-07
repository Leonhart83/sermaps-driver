import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/stop.dart';

/// Salva e ripristina la lista delle tappe in modo che venga mantenuta
/// anche dopo la chiusura dell'app.
class StorageService {
  static const _key = 'stops_v1';
  static const _sessionMetersKey = 'session_meters_v1';
  static const _sessionStartKey = 'session_start_v1';

  static Future<void> saveStops(List<Stop> stops) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(stops.map((s) => s.toJson()).toList());
    await prefs.setString(_key, data);
  }

  static Future<List<Stop>> loadStops() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null || data.isEmpty) return [];
    try {
      final list = jsonDecode(data) as List<dynamic>;
      return list
          .map((e) => Stop.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Salva i dati del giro corrente (km percorsi e ora di inizio) per il
  /// riepilogo, in modo che sopravvivano alla chiusura dell'app.
  static Future<void> saveSession(double meters, DateTime? start) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sessionMetersKey, meters);
    if (start == null) {
      await prefs.remove(_sessionStartKey);
    } else {
      await prefs.setInt(_sessionStartKey, start.millisecondsSinceEpoch);
    }
  }

  /// Ripristina i dati del giro corrente.
  static Future<(double, DateTime?)> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final meters = prefs.getDouble(_sessionMetersKey) ?? 0;
    final startMs = prefs.getInt(_sessionStartKey);
    final start = startMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(startMs);
    return (meters, start);
  }

  static const _skippedUpdateKey = 'skipped_update_version_v1';

  /// Versione di aggiornamento che l'utente ha scelto di rimandare ("Più tardi").
  static Future<String?> getSkippedUpdateVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_skippedUpdateKey);
  }

  /// Ricorda una versione rimandata (per non richiederla a ogni avvio).
  static Future<void> setSkippedUpdateVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedUpdateKey, version);
  }
}
