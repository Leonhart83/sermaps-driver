import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'theme.dart';

export 'theme.dart' show kBrandCopper, kBrandDark;

/// Tema scelto dall'utente (Sistema / Chiaro / Scuro), osservabile dall'app.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);

/// Colore accento scelto dall'utente, osservabile dall'app.
final ValueNotifier<Color> accentColorNotifier =
    ValueNotifier<Color>(kBrandCopper);

/// Colori accento selezionabili (etichetta + colore).
const List<({String label, Color color})> kAccentColors = [
  (label: 'Blu', color: Color(0xFF1A73E8)),
  (label: 'Verde', color: Color(0xFF1E8E3E)),
  (label: 'Viola', color: Color(0xFF6A3DE8)),
  (label: 'Arancio', color: Color(0xFFE8710A)),
  (label: 'Rosso', color: Color(0xFFD93025)),
  (label: 'Teal', color: Color(0xFF00897B)),
];

const _themePrefKey = 'theme_mode';
const _onboardingPrefKey = 'onboarding_done';
const _accentPrefKey = 'accent_color';

ThemeMode _parseThemeMode(String? v) {
  switch (v) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Imposta e salva la modalità tema.
Future<void> setThemeMode(ThemeMode mode) async {
  themeModeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_themePrefKey, mode.name);
}

/// Imposta e salva il colore accento dell'app.
Future<void> setAccentColor(Color color) async {
  accentColorNotifier.value = color;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_accentPrefKey, color.toARGB32());
}

/// Segna l'onboarding come completato (non verrà più mostrato).
Future<void> setOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingPrefKey, true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  themeModeNotifier.value = _parseThemeMode(prefs.getString(_themePrefKey));
  final accent = prefs.getInt(_accentPrefKey);
  if (accent != null) accentColorNotifier.value = Color(accent);
  final onboardingDone = prefs.getBool(_onboardingPrefKey) ?? false;
  runApp(SerMapsApp(onboardingDone: onboardingDone));
}

class SerMapsApp extends StatelessWidget {
  final bool onboardingDone;
  const SerMapsApp({super.key, this.onboardingDone = true});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => ValueListenableBuilder<Color>(
        valueListenable: accentColorNotifier,
        builder: (context, accent, _) => MaterialApp(
          title: 'SerMaps Driver',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(accent),
          darkTheme: AppTheme.dark(accent),
          themeMode: mode,
          builder: (context, child) {
            // Rispetta l'ingrandimento testo del sistema (accessibilità),
            // limitandolo per non rompere il layout su valori estremi.
            final mq = MediaQuery.of(context);
            final scaled = mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            );
            return MediaQuery(
              data: mq.copyWith(textScaler: scaled),
              child: child!,
            );
          },
          home: SplashScreen(onboardingDone: onboardingDone),
        ),
      ),
    );
  }
}

