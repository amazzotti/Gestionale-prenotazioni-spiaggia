import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'availability.dart';
import 'booking_repository.dart';
import 'booking_service.dart';
import 'models.dart';

/// Occupazione del giorno per settore, incassi della stagione e chi deve ancora pagare.
class StatsScreen extends StatefulWidget {
  final List<BeachSector> beachSectors;
  const StatsScreen({super.key, required this.beachSectors});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static final _dayFmt = DateFormat('EEE dd/MM/yyyy', 'it');
  static final _shortFmt = DateFormat('dd/MM');
  DateTime _day = BookingRepository.instance.today;

  Future<void> _markPaid(Booking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Segnare come saldato?'),
        content: Text('${b.clientName} · ombrellone ${b.umbrellaLabel}\nDa incassare ${formatEuro(b.amountDue)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ANNULLA')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('SALDATO')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BookingService.instance.setPaid(b, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incassi e Statistiche'), backgroundColor: Colors.green),
      body: ValueListenableBuilder<List<Booking>?>(
        valueListenable: BookingRepository.instance.bookings,
        builder: (context, bookings, _) {
          if (bookings == null) return const Center(child: CircularProgressIndicator());
          final occupancy = occupancyOn(_day, widget.beachSectors, bookings);
          final totalUmbrellas = occupancy.fold<int>(0, (s, o) => s + o.total);
          final totalOccupied = occupancy.fold<int>(0, (s, o) => s + o.occupied);
          final money = moneySummary(bookings);
          final due = bookingsWithAmountDue(bookings);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Giorno prima',
                        onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day - 1)),
                      ),
                      Expanded(
                        child: Text('Occupazione ${_dayFmt.format(_day)}',
                            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Giorno dopo',
                        onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day + 1)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('Totale: $totalOccupied su $totalUmbrellas', style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 8),
                    for (final o in occupancy)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${o.sector}: ${o.occupied} su ${o.total} (${(o.ratio * 100).round()}%)'),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: o.ratio,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(5),
                            backgroundColor: Colors.green.shade100,
                            color: o.ratio > 0.85 ? Colors.red.shade400 : Colors.green.shade600,
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
              Row(children: [
                Expanded(child: _moneyCard('Incassato', formatEuro(money.collected), Colors.green.shade700, Icons.savings)),
                Expanded(child: _moneyCard('Da incassare', formatEuro(money.due), Colors.orange.shade800, Icons.euro)),
              ]),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Text('Da incassare', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              if (due.isEmpty)
                const Padding(padding: EdgeInsets.all(8), child: Text('Nessun pagamento in sospeso. 🎉'))
              else
                for (final b in due)
                  Card(
                    child: ListTile(
                      title: Text('${b.clientName} - Ombr. ${b.umbrellaLabel}'),
                      subtitle: Text('Dal ${_shortFmt.format(b.startDate)} al ${_shortFmt.format(b.endDate)}'
                          '${b.deposit > 0 ? ' · acconto ${formatEuro(b.deposit)}' : ''}'),
                      trailing: TextButton(onPressed: () => _markPaid(b), child: Text(formatEuro(b.amountDue))),
                    ),
                  ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Gli importi considerano solo le prenotazioni con un prezzo inserito, nella stagione in corso.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _moneyCard(String label, String value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label),
        ]),
      ),
    );
  }
}
