import 'package:url_launcher/url_launcher.dart';

import '../models/stop.dart';

/// Apre Google Maps per avviare la navigazione con le tappe nell'ordine dato.
class MapsLauncher {
  /// Google Maps Directions URL supporta una sola destinazione finale +
  /// fino a ~9 waypoint intermedi.
  static const int maxWaypoints = 9;

  /// Avvia la navigazione passando tutte le tappe (origin = posizione attuale).
  /// Con `dir_action=navigate` Google Maps avvia direttamente la guida.
  /// Restituisce false se non è stato possibile aprire Google Maps.
  static Future<bool> startNavigation(List<Stop> stops) async {
    final geocoded = stops.where((s) => s.isGeocoded).toList();
    if (geocoded.isEmpty) return false;

    // Con una sola tappa, usa l'intent di navigazione diretta (turn-by-turn).
    if (geocoded.length == 1) {
      return openSingle(geocoded.first);
    }

    final destination = geocoded.last;
    final waypoints = geocoded.sublist(0, geocoded.length - 1);

    final params = <String, String>{
      'api': '1',
      'travelmode': 'driving',
      'dir_action': 'navigate',
      'destination': '${destination.lat},${destination.lng}',
    };

    if (waypoints.isNotEmpty) {
      final limited = waypoints.take(maxWaypoints);
      params['waypoints'] =
          limited.map((s) => '${s.lat},${s.lng}').join('|');
    }

    final uri = Uri.https('www.google.com', '/maps/dir/', params);
    return _launch(uri);
  }

  /// Avvia la navigazione turn-by-turn verso una singola tappa.
  /// Usa lo schema `google.navigation:` (parte subito), con fallback al
  /// link web di Google Maps.
  static Future<bool> openSingle(Stop stop) async {
    if (!stop.isGeocoded) return false;
    final navUri =
        Uri.parse('google.navigation:q=${stop.lat},${stop.lng}&mode=d');
    if (await canLaunchUrl(navUri)) {
      return launchUrl(navUri, mode: LaunchMode.externalApplication);
    }
    // Fallback: link web con avvio navigazione.
    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'travelmode': 'driving',
      'dir_action': 'navigate',
      'destination': '${stop.lat},${stop.lng}',
    });
    return _launch(webUri);
  }

  static Future<bool> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
