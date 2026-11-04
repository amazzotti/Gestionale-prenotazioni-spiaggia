import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';

/// Logica "pura" del gestionale: nessun accesso a Firestore o all'interfaccia,
/// così si può testare facilmente.

/// Prenotazioni di un ombrellone che toccano il periodo, ordinate per data.
List<Booking> bookingsInRange(String umbrellaId, DateTimeRange? range, Iterable<Booking> all) {
  if (range == null) return const [];
  return all.where((b) => b.umbrellaId == umbrellaId && b.overlaps(range)).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
}

/// Primo blocco di giorni consecutivi liberi nel periodo (null se è tutto occupato).
DateTimeRange? firstFreeStretch(Iterable<Booking> bookings, DateTimeRange range) {
  final end = dayOnly(range.end);
  DateTime? freeStart;
  DateTime? freeEnd;
  for (var day = dayOnly(range.start); !day.isAfter(end); day = DateTime(day.year, day.month, day.day + 1)) {
    final isFree = !bookings.any((b) => b.coversDay(day));
    if (isFree) {
      freeStart ??= day;
      freeEnd = day;
    } else if (freeStart != null) {
      break;
    }
  }
  return freeStart == null ? null : DateTimeRange(start: freeStart, end: freeEnd!);
}

/// Quadro di un ombrellone attorno a un periodo: chi c'era prima, chi c'è, chi arriva dopo.
class UmbrellaTimeline {
  /// Ultima prenotazione finita prima del periodo (null = nessuna).
  final Booking? previous;

  /// Prenotazioni che toccano il periodo, in ordine di data.
  final List<Booking> inPeriod;

  /// Prima prenotazione che inizia dopo il periodo (null = nessuna).
  final Booking? next;

  final DateTimeRange range;

  const UmbrellaTimeline({required this.range, this.previous, this.inPeriod = const [], this.next});

  /// Giorni liberi tra la prenotazione precedente e l'inizio del periodo.
  int? get freeDaysBefore => previous == null ? null : freeDaysBetween(previous!.endDate, range.start);

  /// Giorni liberi tra la fine del periodo e la prenotazione successiva.
  int? get freeDaysAfter => next == null ? null : freeDaysBetween(range.end, next!.startDate);
}

/// Giorni liberi tra la fine di una prenotazione e l'inizio di un'altra (0 = una subito dopo l'altra).
int freeDaysBetween(DateTime end, DateTime start) {
  final diff = DateTime.utc(start.year, start.month, start.day).difference(DateTime.utc(end.year, end.month, end.day)).inDays - 1;
  return diff < 0 ? 0 : diff;
}

/// Chi c'era prima, chi c'è nel periodo e chi arriva dopo su un ombrellone.
/// [excludeId] esclude la prenotazione che si sta modificando.
UmbrellaTimeline umbrellaTimeline(String umbrellaId, DateTimeRange range, Iterable<Booking> all, {String? excludeId}) {
  final start = dayOnly(range.start);
  final end = dayOnly(range.end);
  Booking? previous;
  Booking? next;
  final inPeriod = <Booking>[];
  for (final b in all) {
    if (b.umbrellaId != umbrellaId) continue;
    if (excludeId != null && excludeId.isNotEmpty && b.id == excludeId) continue;
    if (dayOnly(b.endDate).isBefore(start)) {
      if (previous == null || b.endDate.isAfter(previous.endDate)) previous = b;
    } else if (dayOnly(b.startDate).isAfter(end)) {
      if (next == null || b.startDate.isBefore(next.startDate)) next = b;
    } else {
      inPeriod.add(b);
    }
  }
  inPeriod.sort((a, b) => a.startDate.compareTo(b.startDate));
  return UmbrellaTimeline(range: DateTimeRange(start: start, end: end), previous: previous, inPeriod: inPeriod, next: next);
}

/// "subito", "1 giorno libero", "3 giorni liberi".
String freeDaysText(int days) => days == 0 ? 'subito' : (days == 1 ? '1 giorno libero' : '$days giorni liberi');

/// Prima prenotazione che si sovrappone a [candidate] sullo stesso ombrellone
/// (esclusa la prenotazione stessa, se è una modifica). null = nessun conflitto.
Booking? findConflict(Booking candidate, Iterable<Booking> all) {
  for (final b in all) {
    if (b.umbrellaId != candidate.umbrellaId) continue;
    if (candidate.id.isNotEmpty && b.id == candidate.id) continue;
    if (b.overlaps(candidate.range)) return b;
  }
  return null;
}

/// Chi arriva nel giorno indicato (primo giorno della prenotazione), in ordine alfabetico.
List<Booking> arrivalsOn(DateTime day, Iterable<Booking> all) {
  final d = dayOnly(day);
  return all.where((b) => dayOnly(b.startDate) == d).toList()
    ..sort((a, b) => a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase()));
}

/// Chi parte nel giorno indicato (ultimo giorno della prenotazione), in ordine alfabetico.
List<Booking> departuresOn(DateTime day, Iterable<Booking> all) {
  final d = dayOnly(day);
  return all.where((b) => dayOnly(b.endDate) == d).toList()
    ..sort((a, b) => a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase()));
}

/// Ricerca per nome, telefono o numero di ombrellone (senza distinguere maiuscole).
List<Booking> searchBookings(String query, Iterable<Booking> all) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final qDigits = q.replaceAll(RegExp(r'\D'), '');
  return all.where((b) {
    if (b.clientName.toLowerCase().contains(q)) return true;
    if (b.umbrellaLabel.toLowerCase() == q) return true;
    if (qDigits.length >= 4 && b.phone.replaceAll(RegExp(r'\D'), '').contains(qDigits)) return true;
    return false;
  }).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
}

/// Clienti già visti (nome -> telefono più recente), per l'autocompletamento.
Map<String, String> knownClients(Iterable<Booking> all) {
  final sorted = all.toList()..sort((a, b) => a.startDate.compareTo(b.startDate));
  // chiave in minuscolo -> (nome come scritto più di recente, telefono più recente)
  final byName = <String, (String, String)>{};
  for (final b in sorted) {
    final name = b.clientName.trim();
    if (name.isEmpty || name == 'Senza Nome') continue;
    final previousPhone = byName[name.toLowerCase()]?.$2 ?? '';
    byName[name.toLowerCase()] = (name, b.phone.isNotEmpty ? b.phone : previousPhone);
  }
  return {for (final e in byName.values) e.$1: e.$2};
}

/// Occupazione di un settore in un giorno.
class SectorOccupancy {
  final String sector;
  final int total;
  final int occupied;
  const SectorOccupancy(this.sector, this.total, this.occupied);
  double get ratio => total == 0 ? 0 : occupied / total;
}

List<SectorOccupancy> occupancyOn(DateTime day, List<BeachSector> sectors, Iterable<Booking> all) {
  final busy = all.where((b) => b.coversDay(day)).map((b) => b.umbrellaId).toSet();
  return [
    for (final s in sectors) SectorOccupancy(s.name, s.umbrellas.length, s.umbrellas.where((u) => busy.contains(u.id)).length),
  ];
}

/// Riepilogo incassi della stagione.
class MoneySummary {
  final double collected;
  final double due;
  final int bookingsWithDue;
  const MoneySummary({required this.collected, required this.due, required this.bookingsWithDue});
}

MoneySummary moneySummary(Iterable<Booking> all) {
  var collected = 0.0;
  var due = 0.0;
  var count = 0;
  for (final b in all) {
    collected += b.amountCollected;
    if (b.amountDue > 0) {
      due += b.amountDue;
      count++;
    }
  }
  return MoneySummary(collected: collected, due: due, bookingsWithDue: count);
}

/// Prenotazioni con un importo ancora da incassare, dalla più vicina.
List<Booking> bookingsWithAmountDue(Iterable<Booking> all) =>
    all.where((b) => b.amountDue > 0).toList()..sort((a, b) => a.startDate.compareTo(b.startDate));

/// Numero di telefono nel formato per WhatsApp (solo cifre, con prefisso).
/// I numeri italiani senza prefisso ricevono +39. null se non valido.
String? whatsappNumber(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[\s\-\./()]'), '');
  if (s.isEmpty) return null;
  if (s.startsWith('+')) {
    s = s.substring(1);
  } else if (s.startsWith('00')) {
    s = s.substring(2);
  } else if (RegExp(r'^3\d{8,9}$').hasMatch(s) || RegExp(r'^0\d{5,10}$').hasMatch(s)) {
    s = '39$s';
  }
  if (!RegExp(r'^\d{8,15}$').hasMatch(s)) return null;
  return s;
}

/// Converte un importo scritto dall'utente ("12,50", "€ 30") in numero. null se vuoto o non valido.
double? parseAmountInput(String raw) {
  final s = raw.replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.').trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v < 0 || v.isNaN || v.isInfinite) return null;
  return v;
}

/// Importo in euro in formato italiano: "€ 120" oppure "€ 12,50".
String formatEuro(double value) {
  final rounded = (value * 100).round() / 100;
  final text = rounded == rounded.truncateToDouble() ? rounded.toStringAsFixed(0) : rounded.toStringAsFixed(2).replaceAll('.', ',');
  return '€ $text';
}

/// Messaggio di riepilogo da mandare al cliente (WhatsApp).
String bookingSummaryMessage(Booking b, {String beachName = 'Bagni Carla 98'}) {
  final fmt = DateFormat('dd/MM/yyyy');
  final buffer = StringBuffer()
    ..write('Ciao ${b.clientName}, ti confermiamo la prenotazione dell\'ombrellone ${b.umbrellaLabel} (${b.sectorName}) ')
    ..write('dal ${fmt.format(b.startDate)} al ${fmt.format(b.endDate)}.');
  if (b.price != null && b.price! > 0) {
    buffer.write(' Totale ${formatEuro(b.price!)}');
    if (b.paid) {
      buffer.write(' (saldato)');
    } else if (b.deposit > 0) {
      buffer.write(', acconto versato ${formatEuro(b.deposit)}, da saldare ${formatEuro(b.amountDue)}');
    }
    buffer.write('.');
  }
  buffer.write(' A presto! $beachName');
  return buffer.toString();
}

/// Numero del prossimo ombrellone nell'editor: il più alto già usato + 1 (come nella versione originale).
int nextUmbrellaNumber(Iterable<int> used) => used.fold(0, (max, n) => n > max ? n : max) + 1;

// ---------- Tutto diviso per settore (Mare, Tende, Dietro) ----------

/// Raggruppa le prenotazioni per settore, nell'ordine della mappa (Mare, Tende, Dietro).
/// Mantiene l'ordine delle prenotazioni dentro ogni settore.
List<(String, List<Booking>)> groupBySector(Iterable<Booking> list, List<BeachSector> sectors) {
  final order = BeachSector.sorted(sectors).map((s) => s.name).toList();
  final groups = <String, List<Booking>>{};
  for (final b in list) {
    groups.putIfAbsent(b.sectorName, () => []).add(b);
  }
  // Ordine: quello della mappa; senza mappa, l'ordine fisso Mare, Tende, Dietro.
  int rank(String name) {
    final i = order.indexOf(name);
    return i >= 0 ? i : 100 + (BeachSector.sectorOrder[name] ?? 99);
  }

  final names = groups.keys.toList()..sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.compareTo(b));
  return [for (final n in names) (n, groups[n]!)];
}

/// Incassi di un settore.
class SectorMoney {
  final String sector;
  final MoneySummary money;
  const SectorMoney(this.sector, this.money);
}

/// Incassato e da incassare, separati per settore.
List<SectorMoney> moneyBySector(List<BeachSector> sectors, Iterable<Booking> all) => [
      for (final s in BeachSector.sorted(sectors)) SectorMoney(s.name, moneySummary(all.where((b) => b.sectorName == s.name))),
    ];
