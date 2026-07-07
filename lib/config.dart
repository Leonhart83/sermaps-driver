/// Configurazione dell'app.
///
/// La chiave Google Maps viene usata in due punti:
/// 1) Per disegnare la mappa nativa -> impostata in `android/local.properties`
///    (MAPS_API_KEY) e iniettata nel Manifest.
/// 2) Per le chiamate HTTP (Geocoding / Directions) -> usata qui sotto.
///
/// Puoi passare la chiave senza scriverla nel codice usando:
///   flutter run --dart-define=MAPS_API_KEY=LA_TUA_CHIAVE
/// oppure incollarla direttamente nel valore di default qui sotto.
class AppConfig {
  static const String googleApiKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: 'AIzaSyCcb-P0M6ZM7n6EC9hf6fgpz1tWu2dOVCQ',
  );

  static bool get hasApiKey =>
      googleApiKey.isNotEmpty &&
      googleApiKey != 'INSERISCI_LA_TUA_CHIAVE_QUI';

  /// Repository GitHub (formato "owner/nome") usato per gli aggiornamenti
  /// in-app tramite GitHub Releases. Lascia vuoto per disattivare il controllo.
  ///
  /// Esempio: 'robymrolle/sermaps-driver'
  static const String githubRepo = String.fromEnvironment(
    'GITHUB_REPO',
    defaultValue: 'Leonhart83/sermaps-driver',
  );

  /// True se è stato configurato un repository GitHub valido.
  static bool get hasGithubRepo => githubRepo.contains('/');
}
