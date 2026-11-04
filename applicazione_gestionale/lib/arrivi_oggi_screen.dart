import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'availability.dart';
import 'booking_repository.dart';
import 'booking_service.dart';
import 'contact.dart';
import 'help_screen.dart';
import 'models.dart';

/// Arrivi e partenze di un giorno (di default oggi).
class ArriviOggiScreen extends StatefulWidget {
  final DateTime? initialDate;
  const ArriviOggiScreen({super.key, this.initialDate});

  @override
  State<ArriviOggiScreen> createState() => _ArriviOggiScreenState();
}

class _ArriviOggiScreenState extends State<ArriviOggiScreen> with SingleTickerProviderStateMixin {
  static final _dayFmt = DateFormat('EEEE dd/MM/yyyy', 'it');
  static final _shortFmt = DateFormat('dd/MM');

  late DateTime _selectedDate;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _selectedDate = dayOnly(widget.initialDate ?? BookingRepository.instance.today);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleArrived(Booking b) async {
    try {
      await BookingService.instance.setArrived(b, !b.arrived);
    } catch (e) {
      _showMessage('Errore: $e');
    }
  }

  Future<void> _markPaid(Booking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Segnare come saldato?'),
        content: Text('${b.clientName} · da incassare ${formatEuro(b.amountDue)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ANNULLA')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('SALDATO')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BookingService.instance.setPaid(b, true);
      _showMessage('Pagamento registrato.');
    } catch (e) {
      _showMessage('Errore: $e');
    }
  }

  Future<void> _deleteBooking(Booking b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma Cancellazione'),
        content: Text('Eliminare la prenotazione di ${b.clientName} (ombrellone ${b.umbrellaLabel})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULLA')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ELIMINA', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await BookingService.instance.delete(b);
    } catch (e) {
      _showMessage('Errore: $e');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text('Prenotazione di ${b.clientName} eliminata.'),
      action: SnackBarAction(
        label: 'ANNULLA',
        onPressed: () async {
          try {
            await BookingService.instance.restore(b);
          } catch (e) {
            _showMessage('Impossibile ripristinare: $e');
          }
        },
      ),
    ));
  }

  Future<void> _pickDate() async {
    final windowStart = BookingRepository.instance.windowStart;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _selectedDate.isBefore(windowStart) ? _selectedDate : windowStart,
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) setState(() => _selectedDate = dayOnly(picked));
  }

  void _shiftDay(int delta) =>
      setState(() => _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + delta));

  @override
  Widget build(BuildContext context) {
    final isToday = _selectedDate == BookingRepository.instance.today;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arrivi e Partenze'),
        backgroundColor: Colors.green,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'ARRIVI'), Tab(text: 'PARTENZE')],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate, tooltip: 'Seleziona Data'),
          const HelpButton(HelpTopic.arrivi),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.green.shade100,
            child: Row(children: [
              IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Giorno prima', onPressed: () => _shiftDay(-1)),
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(_dayFmt.format(_selectedDate),
                        textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade900)),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Giorno dopo', onPressed: () => _shiftDay(1)),
              if (!isToday)
                TextButton(onPressed: () => setState(() => _selectedDate = BookingRepository.instance.today), child: const Text('OGGI')),
            ]),
          ),
          Expanded(
            child: ValueListenableBuilder<List<Booking>?>(
              valueListenable: BookingRepository.instance.bookings,
              builder: (context, bookings, _) {
                if (bookings == null) return const Center(child: CircularProgressIndicator());
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(arrivalsOn(_selectedDate, bookings), emptyText: 'Nessun arrivo previsto', showArrived: true),
                    _buildList(departuresOn(_selectedDate, bookings), emptyText: 'Nessuna partenza prevista', showArrived: false),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Booking> list, {required String emptyText, required bool showArrived}) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text('$emptyText per il ${DateFormat('dd/MM/yyyy').format(_selectedDate)}', textAlign: TextAlign.center),
        ),
      );
    }
    // Divisi per settore: prima Mare, poi Tende, poi Dietro.
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final (sector, items) in groupBySector(list, const [])) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Text('${sector.toUpperCase()} · ${items.length}',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.green.shade900)),
          ),
          for (final b in items) _card(b, showArrived: showArrived),
        ],
      ],
    );
  }

  Widget _card(Booking b, {required bool showArrived}) {
    return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: showArrived
                  ? Checkbox(value: b.arrived, activeColor: Colors.green, onChanged: (_) => _toggleArrived(b))
                  : const Icon(Icons.logout, color: Colors.blueGrey),
              title: Text(
                b.clientName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  decoration: showArrived && b.arrived ? TextDecoration.lineThrough : null,
                  color: showArrived && b.arrived ? Colors.grey : null,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ombrellone ${b.umbrellaLabel} · ${b.sectorName}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(showArrived ? 'Fino al ${_shortFmt.format(b.endDate)}' : 'Dal ${_shortFmt.format(b.startDate)}'),
                  if (b.amountDue > 0)
                    InkWell(
                      onTap: () => _markPaid(b),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.euro, size: 16, color: Colors.orange.shade900),
                          const SizedBox(width: 4),
                          Text('Da incassare ${formatEuro(b.amountDue)}',
                              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  if (b.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text('Note: ${b.notes}', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey, fontSize: 13)),
                    ),
                  if (whatsappNumber(b.phone) != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(b.phone, style: const TextStyle(fontSize: 13)),
                      ContactButtons(phone: b.phone),
                    ]),
                ],
              ),
              isThreeLine: true,
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Elimina', onPressed: () => _deleteBooking(b)),
            ),
          ),
        );
  }
}
