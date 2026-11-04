import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'availability.dart';
import 'models.dart';

final _shortFmt = DateFormat('dd/MM');

String _period(Booking b) => 'dal ${_shortFmt.format(b.startDate)} al ${_shortFmt.format(b.endDate)}';

/// Quadro completo di un ombrellone: chi c'era PRIMA, chi c'è NEL PERIODO, chi arriva DOPO.
/// Toccando una prenotazione la si apre per modificarla o spostarla.
class UmbrellaTimelineView extends StatelessWidget {
  final UmbrellaTimeline timeline;
  final void Function(Booking booking) onOpen;

  const UmbrellaTimelineView({super.key, required this.timeline, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = timeline;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SectionTitle(icon: Icons.west, text: 'PRIMA', color: Colors.blueGrey.shade700),
      if (t.previous == null)
        const _EmptyLine('Nessuno prima in questa stagione')
      else ...[
        _BookingTile(booking: t.previous!, color: Colors.blueGrey.shade300, onTap: () => onOpen(t.previous!)),
        _GapLine(t.freeDaysBefore!, before: true),
      ],
      _SectionTitle(icon: Icons.beach_access, text: 'NEL PERIODO ${_shortFmt.format(t.range.start)} - ${_shortFmt.format(t.range.end)}', color: Colors.red.shade700),
      if (t.inPeriod.isEmpty)
        _EmptyLine('Libero in questo periodo', color: Colors.green.shade800)
      else
        for (final b in t.inPeriod) _BookingTile(booking: b, color: Colors.red.shade400, bold: true, onTap: () => onOpen(b)),
      _SectionTitle(icon: Icons.east, text: 'DOPO', color: Colors.blueGrey.shade700),
      if (t.next == null)
        const _EmptyLine('Nessuno dopo in questa stagione')
      else ...[
        _GapLine(t.freeDaysAfter!, before: false),
        _BookingTile(booking: t.next!, color: Colors.blueGrey.shade300, onTap: () => onOpen(t.next!)),
      ],
    ]);
  }
}

/// Versione compatta per la scheda prenotazione: una riga per "prima" e una per "dopo".
class NeighborsBox extends StatelessWidget {
  final UmbrellaTimeline timeline;
  const NeighborsBox({super.key, required this.timeline});

  @override
  Widget build(BuildContext context) {
    final prev = timeline.previous;
    final next = timeline.next;
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: Colors.blueGrey.shade700),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade900))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        line(Icons.west,
            prev == null ? 'Prima: nessuno' : 'Prima: ${prev.clientName}, fino al ${_shortFmt.format(prev.endDate)} (${freeDaysText(timeline.freeDaysBefore!)})'),
        line(Icons.east,
            next == null ? 'Dopo: nessuno' : 'Dopo: ${next.clientName}, dal ${_shortFmt.format(next.startDate)} (${freeDaysText(timeline.freeDaysAfter!)})'),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _SectionTitle({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5))),
        ]),
      );
}

class _EmptyLine extends StatelessWidget {
  final String text;
  final Color? color;
  const _EmptyLine(this.text, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 2, 16, 4),
        child: Text(text, style: TextStyle(color: color ?? Colors.grey.shade600, fontStyle: FontStyle.italic)),
      );
}

class _GapLine extends StatelessWidget {
  final int days;
  final bool before;
  const _GapLine(this.days, {required this.before});

  @override
  Widget build(BuildContext context) {
    final text = days == 0
        ? (before ? 'finisce il giorno prima del periodo' : 'arriva il giorno dopo il periodo')
        : (before ? 'poi ${freeDaysText(days)} prima del periodo' : '${freeDaysText(days)} dopo il periodo');
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 16, 2),
      child: Text(text, style: TextStyle(fontSize: 12, color: days == 0 ? Colors.blueGrey : Colors.green.shade800)),
    );
  }
}

class _BookingTile extends StatelessWidget {
  final Booking booking;
  final Color color;
  final bool bold;
  final VoidCallback onTap;
  const _BookingTile({required this.booking, required this.color, required this.onTap, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return ListTile(
      dense: true,
      leading: Container(width: 6, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      minLeadingWidth: 10,
      title: Text(b.clientName, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      subtitle: Text([
        _period(b),
        if (b.amountDue > 0) 'da incassare ${formatEuro(b.amountDue)}',
        if (b.notes.isNotEmpty) b.notes,
      ].join(' · ')),
      trailing: const Icon(Icons.edit, size: 18),
      onTap: onTap,
    );
  }
}
