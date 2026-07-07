import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config.dart';

/// Una previsione di autocompletamento indirizzo.
class Prediction {
  final String description;
  final String placeId;
  Prediction(this.description, this.placeId);
}

/// Servizio di autocompletamento indirizzi tramite Google Places API.
class PlacesService {
  static const _autocomplete =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';

  /// Token di sessione: riduce i costi raggruppando le richieste.
  String _sessionToken = const Uuid().v4();

  void newSession() => _sessionToken = const Uuid().v4();

  /// Restituisce previsioni per il testo digitato.
  Future<List<Prediction>> autocomplete(String input) async {
    if (input.trim().length < 3 || !AppConfig.hasApiKey) return [];

    final uri = Uri.parse(_autocomplete).replace(queryParameters: {
      'input': input,
      'key': AppConfig.googleApiKey,
      'language': 'it',
      'components': 'country:it',
      'sessiontoken': _sessionToken,
    });

    try {
      final resp = await http.get(uri);
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') return [];
      final preds = data['predictions'] as List<dynamic>;
      return preds
          .map((p) => Prediction(
                (p as Map<String, dynamic>)['description'] as String,
                p['place_id'] as String,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
