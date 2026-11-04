import 'package:flutter/material.dart';

import 'availability.dart';
import 'models.dart';

/// Aspetto di ogni settore: stessa icona e stesso colore in tutta l'app,
/// così si riconosce subito se una prenotazione è in Mare, Tende o Dietro.
class SectorStyle {
  final IconData icon;
  final Color color;
  const SectorStyle(this.icon, this.color);

  static SectorStyle of(String sectorName) {
    switch (sectorName) {
      case 'Mare':
        return SectorStyle(Icons.waves, Colors.blue.shade700);
      case 'Tende':
        return SectorStyle(Icons.festival, Colors.purple.shade400);
      case 'Dietro':
        return SectorStyle(Icons.beach_access, Colors.teal.shade600);
      default:
        return SectorStyle(Icons.grid_view, Colors.blueGrey.shade600);
    }
  }
}

/// Etichetta colorata del settore (es. nella scheda prenotazione e nella ricerca).
class SectorBadge extends StatelessWidget {
  final String sectorName;
  final String? text;
  const SectorBadge(this.sectorName, {super.key, this.text});

  @override
  Widget build(BuildContext context) {
    final style = SectorStyle.of(sectorName);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(style.icon, size: 16, color: style.color),
        const SizedBox(width: 6),
        Text(text ?? sectorName, style: TextStyle(color: style.color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

/// Ombrelloni di un settore liberi per TUTTO il periodo.
int freeUmbrellas(BeachSector sector, DateTimeRange range, Iterable<Booking> bookings) {
  final all = bookings.toList();
  return sector.umbrellas.where((u) => bookingsInRange(u.id, range, all).isEmpty).length;
}

/// Barra per scegliere il settore, con quanti ombrelloni sono liberi nel periodo.
/// [selected] null = tutti i settori.
class SectorBar extends StatelessWidget {
  final List<BeachSector> sectors;
  final String? selected;
  final DateTimeRange range;
  final List<Booking> bookings;
  final ValueChanged<String?> onSelected;

  const SectorBar({
    super.key,
    required this.sectors,
    required this.selected,
    required this.range,
    required this.bookings,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = BeachSector.sorted(sectors);
    final totalFree = sorted.fold<int>(0, (s, sec) => s + freeUmbrellas(sec, range, bookings));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(children: [
        _option(context, null, 'Tutti', Icons.apps, Colors.green.shade800, totalFree),
        for (final s in sorted)
          _option(context, s.name, s.name, SectorStyle.of(s.name).icon, SectorStyle.of(s.name).color, freeUmbrellas(s, range, bookings)),
      ]),
    );
  }

  Widget _option(BuildContext context, String? value, String label, IconData icon, Color color, int free) {
    final isSelected = selected == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Semantics(
          button: true,
          selected: isSelected,
          label: '$label, $free liberi',
          child: Material(
            color: isSelected ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: ExcludeSemantics(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 16, color: isSelected ? Colors.white : color),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : color)),
                      ),
                    ]),
                    Text(free == 1 ? '1 libero' : '$free liberi',
                        style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.grey.shade800)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scelta del settore all'inizio di una nuova prenotazione, con i posti liberi per il periodo.
Future<String?> chooseSector(
  BuildContext context, {
  required List<BeachSector> sectors,
  required DateTimeRange range,
  required List<Booking> bookings,
}) {
  final days = daysBetween(range.start, range.end) + 1;
  String two(int n) => n.toString().padLeft(2, '0');
  final period = 'dal ${two(range.start.day)}/${two(range.start.month)} al ${two(range.end.day)}/${two(range.end.month)}';
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('In quale settore?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Posti liberi per tutto il periodo, $period (${days == 1 ? '1 giorno' : '$days giorni'})',
              style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          for (final s in BeachSector.sorted(sectors))
            Builder(builder: (_) {
              final style = SectorStyle.of(s.name);
              final free = freeUmbrellas(s, range, bookings);
              return Card(
                color: style.color.withValues(alpha: 0.07),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: style.color.withValues(alpha: 0.4))),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: CircleAvatar(backgroundColor: style.color, child: Icon(style.icon, color: Colors.white)),
                  title: Text(s.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: style.color)),
                  subtitle: Text(free == 0 ? 'Pieno per queste date' : '$free liberi su ${s.umbrellas.length}',
                      style: TextStyle(color: free == 0 ? Colors.red.shade700 : Colors.grey.shade800)),
                  trailing: Icon(Icons.chevron_right, color: style.color),
                  onTap: () => Navigator.pop(sheetContext, s.name),
                ),
              );
            }),
        ]),
      ),
    ),
  );
}
