import 'package:geolocator/geolocator.dart';

/// Servizio per ottenere la posizione GPS dell'utente.
class LocationService {
  /// Richiede i permessi e restituisce la posizione attuale.
  /// Lancia un'eccezione con messaggio leggibile in caso di problemi.
  static Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Il GPS è disattivato. Attivalo per continuare.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permesso posizione negato.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Permesso posizione negato in modo permanente. '
        'Abilitalo dalle impostazioni del telefono.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  /// Distanza in metri tra due coordinate (in linea d'aria).
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }
}
