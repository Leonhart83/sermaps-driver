import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/places_service.dart';

/// Foglio per aggiungere un indirizzo con autocompletamento.
/// Restituisce la stringa dell'indirizzo selezionato (o digitato), oppure null.
class AddAddressSheet extends StatefulWidget {
  const AddAddressSheet({super.key});

  @override
  State<AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends State<AddAddressSheet>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _places = PlacesService();
  List<Prediction> _predictions = [];
  Timer? _debounce;
  bool _loading = false;

  // Riconoscimento vocale
  final _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  /// Locale effettivamente usato per la dettatura (scelto tra quelli
  /// disponibili sul dispositivo; l'italiano potrebbe non essere it_IT).
  String? _speechLocaleId;

  /// Animazione "pulsante" mostrata mentre il microfono ascolta.
  late final AnimationController _pulse;

  /// Mappa parola-numero -> valore (0-999), costruita all'avvio.
  final Map<String, int> _numberWords = {};

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _buildNumberWords();
    _initSpeech();
  }

  /// Costruisce la tabella dei numeri italiani a parole per i civici (0-999),
  /// includendo le forme elise (es. "ventuno", "centotto", "centuno").
  void _buildNumberWords() {
    const base = [
      'zero', 'uno', 'due', 'tre', 'quattro', 'cinque', 'sei', 'sette',
      'otto', 'nove', 'dieci', 'undici', 'dodici', 'tredici', 'quattordici',
      'quindici', 'sedici', 'diciassette', 'diciotto', 'diciannove',
    ];
    const tens = {
      2: 'venti', 3: 'trenta', 4: 'quaranta', 5: 'cinquanta',
      6: 'sessanta', 7: 'settanta', 8: 'ottanta', 9: 'novanta',
    };

    String spellUnder100(int n) {
      if (n < 20) return base[n];
      final t = n ~/ 10;
      final u = n % 10;
      final root = tens[t]!;
      if (u == 0) return root;
      // Elisione della vocale finale davanti a "uno" (1) e "otto" (8).
      if (u == 1 || u == 8) {
        return '${root.substring(0, root.length - 1)}${base[u]}';
      }
      return '$root${base[u]}';
    }

    for (var n = 0; n <= 999; n++) {
      String word;
      if (n < 100) {
        word = spellUnder100(n);
      } else {
        final h = n ~/ 100;
        final rem = n % 100;
        final prefix = '${h == 1 ? '' : base[h]}cento';
        if (rem == 0) {
          word = prefix;
        } else {
          final remWord = spellUnder100(rem);
          word = '$prefix$remWord';
          // Variante elisa: "cento" perde la "o" davanti a "uno"/"otto".
          if (remWord.startsWith('uno') || remWord.startsWith('otto')) {
            _numberWords['${prefix.substring(0, prefix.length - 1)}$remWord'] = n;
          }
        }
      }
      _numberWords[word] = n;
    }
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _listening = false);
          // Ignora i "non ho capito" (silenzio o nessuna corrispondenza):
          // non sono errori bloccanti e comparirebbero di continuo.
          final msg = error.errorMsg;
          if (msg == 'error_no_match' || msg == 'error_speech_timeout') return;
          _showSpeechError('Errore riconoscimento vocale: $msg');
        },
      );
      // Sceglie la migliore lingua italiana tra quelle installate sul
      // dispositivo: su molti telefoni l'id non e' esattamente "it_IT".
      if (available) {
        try {
          final locales = await _speech.locales();
          final it = locales.firstWhere(
            (l) => l.localeId.toLowerCase().replaceAll('-', '_').startsWith('it'),
            orElse: () => locales.isNotEmpty
                ? locales.first
                : throw StateError('no-locales'),
          );
          _speechLocaleId = it.localeId;
        } catch (_) {
          _speechLocaleId = null; // usa il default di sistema
        }
      }
      if (mounted) setState(() => _speechAvailable = available);
    } catch (e) {
      if (mounted) setState(() => _speechAvailable = false);
      _showSpeechError('Impossibile avviare il microfono: $e');
    }
  }

  /// Mostra un messaggio d'errore del riconoscimento vocale (se il widget
  /// e' ancora montato).
  void _showSpeechError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Riconoscimento vocale non disponibile.'),
        ),
      );
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: _speechLocaleId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
      ),
      onResult: (result) {
        if (!mounted) return;
        final text = _numberWordsToDigits(result.recognizedWords);
        _controller.text = text;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        _onChanged(_controller.text);
      },
    );
  }

  /// Converte i numeri dettati a parole in cifre (utile per i civici).
  /// Es. "via roma centotrentotto" -> "via roma 138".
  String _numberWordsToDigits(String input) {
    if (input.isEmpty) return input;
    final tokens = input.split(RegExp(r'\s+'));
    final out = <String>[];
    for (final token in tokens) {
      final clean = token
          .toLowerCase()
          .replaceAll(RegExp(r'[àáâ]'), 'a')
          .replaceAll(RegExp(r'[èéê]'), 'e')
          .replaceAll(RegExp(r'[^a-z]'), '');
      final n = _numberWords[clean];
      out.add(n != null ? n.toString() : token);
    }
    return out.join(' ');
  }

  @override
  void dispose() {
    _pulse.dispose();
    _speech.stop();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _loading = true);
      final preds = await _places.autocomplete(value);
      if (!mounted) return;
      setState(() {
        _predictions = preds;
        _loading = false;
      });
    });
  }

  void _confirm(String address) {
    Navigator.of(context).pop(address);
  }

  /// Pulsante microfono: statico se inattivo, con alone pulsante in ascolto.
  Widget _buildMicButton() {
    final cs = Theme.of(context).colorScheme;
    if (!_listening) {
      return IconButton(
        icon: const Icon(Icons.mic_none),
        tooltip: 'Detta indirizzo',
        onPressed: _toggleListening,
      );
    }
    return GestureDetector(
      onTap: _toggleListening,
      child: Tooltip(
        message: 'Ferma dettatura',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 26 + 18 * t,
                      height: 26 + 18 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary.withValues(alpha: 0.20 * (1 - t)),
                      ),
                    ),
                    Icon(Icons.mic, color: cs.primary),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Banner "In ascolto…" con puntino pulsante mentre si detta.
  Widget _buildListeningBanner() {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: !_listening
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary.withValues(
                          alpha: 0.4 + 0.6 * _pulse.value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'In ascolto… parla pure',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.mic, size: 18, color: cs.primary),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _confirm(v.trim());
                  },
                  decoration: InputDecoration(
                    hintText: 'Cerca un indirizzo...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Cancella',
                            onPressed: () {
                              _controller.clear();
                              setState(() => _predictions = []);
                            },
                          ),
                        if (_speechAvailable) _buildMicButton(),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              _buildListeningBanner(),
              Expanded(
                child: _predictions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _controller.text.trim().length < 3
                                ? 'Digita almeno 3 caratteri per i suggerimenti.\n'
                                    'Puoi anche premere Invio per usare il testo digitato.'
                                : 'Nessun suggerimento.\nPremi Invio per usare il testo digitato.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _predictions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _predictions[i];
                          return ListTile(
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(p.description),
                            onTap: () => _confirm(p.description),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
