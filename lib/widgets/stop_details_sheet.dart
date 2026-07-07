import 'package:flutter/material.dart';

import '../models/stop.dart';

/// Valori restituiti dal foglio "Dettagli tappa".
class StopDetailsResult {
  final ServiceType serviceType;
  final String? note;
  final bool continuousHours;
  final int? lunchStartMinutes;
  final int? lunchEndMinutes;

  const StopDetailsResult({
    required this.serviceType,
    required this.note,
    required this.continuousHours,
    required this.lunchStartMinutes,
    required this.lunchEndMinutes,
  });
}

/// Foglio per impostare tipo di intervento, note e orari di una tappa.
class StopDetailsSheet extends StatefulWidget {
  const StopDetailsSheet({super.key, required this.stop, this.isNew = false});

  final Stop stop;

  /// True quando il foglio è mostrato subito dopo aver aggiunto la tappa.
  final bool isNew;

  @override
  State<StopDetailsSheet> createState() => _StopDetailsSheetState();
}

class _StopDetailsSheetState extends State<StopDetailsSheet> {
  late ServiceType _serviceType;
  late final TextEditingController _noteController;
  late bool _continuous;
  int? _lunchStart;
  int? _lunchEnd;

  @override
  void initState() {
    super.initState();
    _serviceType = widget.stop.serviceType;
    _noteController = TextEditingController(text: widget.stop.note ?? '');
    _continuous = widget.stop.continuousHours;
    _lunchStart = widget.stop.lunchStartMinutes;
    _lunchEnd = widget.stop.lunchEndMinutes;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickLunch({required bool start}) async {
    final current = start ? _lunchStart : _lunchEnd;
    final initial = current != null
        ? TimeOfDay(hour: current ~/ 60, minute: current % 60)
        : TimeOfDay(hour: start ? 13 : 15, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: start ? 'Chiusura pranzo dalle' : 'Riapertura alle',
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (start) {
        _lunchStart = minutes;
      } else {
        _lunchEnd = minutes;
      }
    });
  }

  void _save() {
    Navigator.of(context).pop(
      StopDetailsResult(
        serviceType: _serviceType,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        continuousHours: _continuous,
        lunchStartMinutes: _continuous ? null : _lunchStart,
        lunchEndMinutes: _continuous ? null : _lunchEnd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.isNew)
                Text(
                  'Dettagli intervento',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              if (widget.isNew) const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.place, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.stop.address,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.isNew) ...[
                const SizedBox(height: 6),
                Text(
                  'Puoi lasciare vuoto: verrà segnato come "Non definito".',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 22),

              // Tipo di intervento
              _sectionHeader(Icons.build_circle_outlined, 'Tipo di intervento'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ServiceType.values.map((t) {
                  final selected = _serviceType == t;
                  return ChoiceChip(
                    label: Text(t.label),
                    selected: selected,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.onPrimary : null,
                    ),
                    selectedColor: cs.primary,
                    onSelected: (_) => setState(() => _serviceType = t),
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),

              // Note
              _sectionHeader(Icons.sticky_note_2_outlined, 'Note'),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Aggiungi una nota (es. citofonare, referente...)',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // Orari
              _sectionHeader(Icons.lunch_dining, 'Pausa pranzo'),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Orario continuato'),
                subtitle: const Text('Aperto tutto il giorno, nessuna pausa'),
                value: _continuous,
                onChanged: (v) => setState(() => _continuous = v),
              ),
              if (!_continuous) ...[
                const SizedBox(height: 4),
                Text(
                  'Indica quando chiude per pranzo',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(
                          _lunchStart == null
                              ? 'Dalle'
                              : Stop.formatMinutes(_lunchStart!),
                        ),
                        onPressed: () => _pickLunch(start: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(
                          _lunchEnd == null
                              ? 'Alle'
                              : Stop.formatMinutes(_lunchEnd!),
                        ),
                        onPressed: () => _pickLunch(start: false),
                      ),
                    ),
                  ],
                ),
                if (_lunchStart != null || _lunchEnd != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Rimuovi pausa'),
                      onPressed: () => setState(() {
                        _lunchStart = null;
                        _lunchEnd = null;
                      }),
                    ),
                  ),
              ],
              const SizedBox(height: 26),
              Row(
                children: [
                  if (widget.isNew) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Salta'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, size: 20),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(widget.isNew ? 'Conferma' : 'Salva'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Intestazione di sezione con icona.
  Widget _sectionHeader(IconData icon, String title) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 19, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );
  }
}
