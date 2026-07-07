import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';

/// Informazioni su una nuova versione disponibile su GitHub Releases.
class UpdateInfo {
  /// Versione della release (tag ripulito, es. "1.1.0").
  final String version;

  /// URL diretto dell'APK da scaricare.
  final String apkUrl;

  /// Note della release (campo "body" della release GitHub).
  final String? notes;

  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    this.notes,
  });
}

/// Controlla se è disponibile una versione più recente dell'app pubblicata
/// su GitHub Releases e ne espone i dati per l'installazione.
class UpdateService {
  /// Interroga l'ultima release del repository configurato e restituisce le
  /// informazioni solo se la versione è più recente di quella installata.
  /// Restituisce null se il repo non è configurato, in caso di errore di rete
  /// o se l'app è già aggiornata.
  static Future<UpdateInfo?> checkForUpdate() async {
    if (!AppConfig.hasGithubRepo) return null;

    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/${AppConfig.githubRepo}/releases/latest',
      );
      final res = await http.get(
        uri,
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty) return null;

      // Trova il primo asset .apk allegato alla release.
      final assets = (data['assets'] as List?) ?? const [];
      String? apkUrl;
      for (final a in assets) {
        final name = (a['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) return null;

      final info = await PackageInfo.fromPlatform();
      final latest = _parseVersion(tag);
      final current = _parseVersion(info.version);
      if (!_isNewer(latest, current)) return null;

      return UpdateInfo(
        version: tag.replaceFirst(RegExp(r'^v'), ''),
        apkUrl: apkUrl,
        notes: (data['body'] as String?)?.trim(),
      );
    } catch (_) {
      // Errori di rete/parse non devono bloccare l'app.
      return null;
    }
  }

  /// Converte una stringa di versione (es. "v1.2.3", "1.2.3+4") in una lista
  /// di numeri per il confronto (i suffissi non numerici vengono ignorati).
  static List<int> _parseVersion(String raw) {
    final cleaned = raw.replaceFirst(RegExp(r'^v'), '');
    final core = cleaned.split('+').first.split('-').first;
    return core
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  /// True se [latest] è una versione successiva a [current].
  static bool _isNewer(List<int> latest, List<int> current) {
    final len = latest.length > current.length ? latest.length : current.length;
    for (var i = 0; i < len; i++) {
      final a = i < latest.length ? latest[i] : 0;
      final b = i < current.length ? current[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }
}
