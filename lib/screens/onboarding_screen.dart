import 'package:flutter/material.dart';

import '../main.dart' show kBrandCopper, setOnboardingDone;
import 'home_screen.dart';

/// Schermata introduttiva mostrata al primo avvio dell'app.
class OnboardingScreen extends StatefulWidget {
  /// True se aperta dal menu (per rivederla): al termine torna indietro
  /// invece di proseguire alla home.
  final bool fromMenu;
  const OnboardingScreen({super.key, this.fromMenu = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = <_Slide>[
    _Slide(
      icon: Icons.local_shipping_outlined,
      title: 'Benvenuto in SerMaps Driver',
      text: 'Organizza le tue consegne in pochi tocchi: indirizzi, percorso e '
          'navigazione, tutto in un\'unica app.',
    ),
    _Slide(
      icon: Icons.add_location_alt_outlined,
      title: 'Aggiungi gli indirizzi',
      text: 'Cerca un indirizzo con i suggerimenti, oppure incolla un\'intera '
          'lista (uno per riga).',
    ),
    _Slide(
      icon: Icons.alt_route,
      title: 'Percorso e orari',
      text: 'L\'app ordina le tappe dalla più vicina a te, calcola distanze e '
          'orari di arrivo e ti avvisa se sei in ritardo.',
    ),
    _Slide(
      icon: Icons.navigation_outlined,
      title: 'Avvia la navigazione',
      text: 'Con un tocco apri Google Maps e parte la guida lungo il giro. '
          'Segna le consegne fatte e prosegui.',
    ),
  ];

  Future<void> _finish() async {
    if (widget.fromMenu) {
      Navigator.of(context).pop();
      return;
    }
    await setOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLast = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(isLast ? '' : 'Salta'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: kBrandCopper.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(s.icon, size: 68, color: kBrandCopper),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          s.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Indicatori (puntini)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? kBrandCopper : cs.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (isLast) {
                      _finish();
                    } else {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  child: Text(isLast ? 'Inizia' : 'Avanti'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Creata da Roberto Rolle',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final String title;
  final String text;
  const _Slide({required this.icon, required this.title, required this.text});
}
