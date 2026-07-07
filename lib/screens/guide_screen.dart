import 'package:flutter/material.dart';

import '../main.dart' show kBrandCopper;

/// Schermata "Guida" in-app: spiega l'uso dell'app con testo e immagini.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Guida')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _intro(context),
          const SizedBox(height: 8),
          _section(
            context,
            n: 1,
            title: 'Prima schermata',
            body:
                'All\'avvio vedi la mappa centrata sulla tua posizione e il pannello '
                'in basso con i pulsanti per aggiungere indirizzi.',
            image: 'assets/guide/01-home-vuota.png',
          ),
          _section(
            context,
            n: 2,
            title: 'Aggiungere le tappe',
            bullets: const [
              'Aggiungi: cerca un indirizzo con i suggerimenti automatici. Se è '
                  'ambiguo, scegli tu il risultato giusto.',
              'Detta a voce: tocca il microfono e pronuncia l\'indirizzo. I '
                  'numeri civici detti a parole (es. "centotrentotto") vengono '
                  'convertiti in cifre e i suggerimenti compaiono mentre parli.',
              'Incolla lista: incolla più indirizzi insieme, uno per riga.',
            ],
          ),
          _section(
            context,
            n: 3,
            title: 'Dettagli intervento',
            body:
                'Appena scegli un indirizzo, l\'app chiede il tipo di intervento '
                '(LIS, IGT, SISAL, TLC, GBO, GLOBAL), eventuali note e gli orari '
                'del punto vendita (apertura, chiusura e pausa pranzo, oppure '
                'orario continuato). '
                'Puoi premere "Salta": resterà segnato come "Non definito" e '
                'potrai completarlo più tardi dal menu ⋮ → "Dettagli / note". '
                'Tipo e nota compaiono in alto a destra sulla tappa.',
          ),
          _section(
            context,
            n: 4,
            title: 'Il percorso sulla mappa',
            body:
                'Con le tappe inserite, l\'app traccia il percorso con i marcatori '
                'numerati nell\'ordine di visita e mostra distanza, tempo totale e '
                'l\'orario di arrivo stimato per ogni tappa.',
            image: 'assets/guide/02-percorso.png',
          ),
          _section(
            context,
            n: 5,
            title: 'Ordinare e gestire',
            bullets: const [
              'Auto-ordina: riordina partendo dalla tappa più vicina a te e, se '
                  'hai indicato gli orari dei punti vendita, ti porta a ogni '
                  'negozio quando è aperto, rimandando le tappe a cui arriveresti '
                  'a negozio chiuso (prima dell\'apertura, in pausa o dopo la '
                  'chiusura).',
              'Trascina una tappa (icona ☰) per spostarla a mano.',
              'Menu ⋮ su ogni tappa: sposta, blocca come prima/ultima, imposta '
                  'orario, dettagli/note, apri in Maps, elimina.',
              'Scorri a sinistra per eliminare una tappa.',
            ],
          ),
          _section(
            context,
            n: 6,
            title: 'Stato consegne',
            body:
                'Tocca la spunta verde per segnare una tappa come consegnata: '
                'esce dalla lista, il pin diventa verde e il percorso si ricalcola. '
                'La barra in alto mostra l\'avanzamento del giro.',
            image: 'assets/guide/05-consegnata.png',
          ),
          _section(
            context,
            n: 7,
            title: 'Orari di consegna e pause',
            body:
                'Dal menu ⋮ di una tappa imposta un orario "entro le": l\'app '
                'calcola l\'arrivo stimato e, se sei in ritardo, evidenzia la tappa '
                'in rosso. Se un punto chiude a pranzo e ci arriveresti durante la '
                'chiusura, vedi l\'avviso "Chiuso a pranzo".',
            image: 'assets/guide/07-ritardo.png',
          ),
          _section(
            context,
            n: 8,
            title: 'Avviare la navigazione',
            bullets: const [
              'Avvia navigazione: apre Google Maps e parte la guida lungo il giro '
                  '(a blocchi di 10 tappe se sono di più).',
              'Prossima: naviga subito verso la prossima tappa da fare.',
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Creata da Roberto Rolle',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) {
    return Card(
      color: kBrandCopper.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SerMaps Driver',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Incolla o cerca gli indirizzi, ottimizza il percorso, controlla gli '
              'orari di arrivo e avvia la navigazione con Google Maps.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required int n,
    required String title,
    String? body,
    List<String>? bullets,
    String? image,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: kBrandCopper,
                foregroundColor: Colors.white,
                child: Text('$n',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (body != null)
            Text(body, style: TextStyle(color: cs.onSurface, height: 1.4)),
          if (bullets != null)
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 6, color: kBrandCopper),
                    ),
                    Expanded(
                      child: Text(b, style: TextStyle(color: cs.onSurface, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),
          if (image != null) ...[
            const SizedBox(height: 12),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  image,
                  width: 240,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
