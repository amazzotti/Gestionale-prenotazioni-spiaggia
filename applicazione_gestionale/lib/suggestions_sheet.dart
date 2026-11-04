import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'suggester.dart';

/// Pannello "Dove la metto?": consiglia gli ombrelloni migliori per il periodo.
Future<void> showSuggestionsSheet(
  BuildContext context, {
  required DateTimeRange range,
  required List<BeachSector> sectors,
  required List<Booking> bookings,
  required void Function(Umbrella umbrella, String clientName) onChoose,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: SuggestionsPanel(
        range: range,
        sectors: sectors,
        bookings: bookings,
        onChoose: (u, name) {
          Navigator.pop(sheetContext);
          onChoose(u, name);
        },
      ),
    ),
  );
}

class SuggestionsPanel extends StatefulWidget {
  final DateTimeRange range;
  final List<BeachSector> sectors;
  final List<Booking> bookings;
  final void Function(Umbrella umbrella, String clientName) onChoose;

  const SuggestionsPanel({super.key, required this.range, required this.sectors, required this.bookings, required this.onChoose});

  @override
  State<SuggestionsPanel> createState() => _SuggestionsPanelState();
}

class _SuggestionsPanelState extends State<SuggestionsPanel> {
  static final _fmt = DateFormat('dd/MM');
  String? _sector;
  final _client = TextEditingController();

  @override
  void initState() {
    super.initState();
    _client.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  List<UmbrellaSuggestion> _suggest(String? sector) => suggestUmbrellas(
        range: widget.range,
        sectors: widget.sectors,
        bookings: widget.bookings,
        sectorName: sector,
        clientName: _client.text,
      );

  @override
  Widget build(BuildContext context) {
    var list = _suggest(_sector);
    String? note;
    if (list.isEmpty && _sector != null) {
      list = _suggest(null);
      note = list.isEmpty ? null : 'Nessun posto libero in $_sector per queste date. Ecco gli altri settori:';
    }
    final days = widget.range.end.difference(widget.range.start).inDays + 1;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(children: [
            Icon(Icons.lightbulb, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            const Expanded(child: Text('Dove la metto?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 4),
          Text('Dal ${_fmt.format(widget.range.start)} al ${_fmt.format(widget.range.end)} · ${days == 1 ? '1 giorno' : '$days giorni'}',
              style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [
            ChoiceChip(label: const Text('Tutti'), selected: _sector == null, onSelected: (_) => setState(() => _sector = null)),
            for (final s in BeachSector.sorted(widget.sectors))
              ChoiceChip(label: Text(s.name), selected: _sector == s.name, onSelected: (_) => setState(() => _sector = s.name)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _client,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Cliente (facoltativo)',
              helperText: 'Se è già stato da voi, vi propongo il suo ombrellone',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          if (note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note, style: TextStyle(color: Colors.orange.shade900))),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Nessun ombrellone libero per tutto il periodo. Prova a cambiare le date o a dividere la prenotazione.',
                  textAlign: TextAlign.center),
            ),
          for (var i = 0; i < list.length; i++) _card(list[i], best: i == 0),
          const SizedBox(height: 8),
          Text(
            'Come scelgo: prima l\'ombrellone abituale del cliente, poi quelli dove la prenotazione si incastra tra due clienti '
            'senza lasciare giorni scomodi. Gli ombrelloni completamente liberi restano per chi si ferma di più.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _card(UmbrellaSuggestion s, {required bool best}) {
    return Card(
      color: best ? Colors.green.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (best) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.star, color: Colors.amber.shade700, size: 20)),
            Expanded(
              child: Text('Ombrellone ${s.umbrella.simpleId} · ${s.umbrella.sectorName}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ]),
          for (final r in s.reasons) Padding(padding: const EdgeInsets.only(top: 2), child: Text(r)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => widget.onChoose(s.umbrella, _client.text.trim()),
              icon: const Icon(Icons.add),
              label: const Text('PRENOTA QUI'),
            ),
          ),
        ]),
      ),
    );
  }
}
