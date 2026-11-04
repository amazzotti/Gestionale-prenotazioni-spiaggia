import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Normalizza una data a mezzanotte (ignora ore e minuti).
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Giorni di calendario da [a] a [b] (0 = stesso giorno). Calcolato in UTC,
/// così non sbaglia di un giorno al cambio dell'ora legale.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Il giorno dopo (o prima, con [n] negativo), senza problemi di ora legale.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Stato del pagamento di una prenotazione.
enum PaymentStatus {
  /// Nessun prezzo inserito.
  none,

  /// Prezzo inserito ma non ancora saldato.
  due,

  /// Saldato.
  paid,
}

// --- MODELLO DATI PRENOTAZIONE ---
class Booking {
  final String id;
  final String umbrellaId;
  final String clientName;
  final DateTime startDate;
  final DateTime endDate;
  final String notes;
  final bool arrived;
  final String phone;

  /// Prezzo totale concordato (null = non inserito).
  final double? price;

  /// Acconto già versato.
  final double deposit;

  /// true quando il cliente ha saldato tutto.
  final bool paid;

  /// Ultimo utente che ha modificato la prenotazione (email).
  final String? updatedBy;

  Booking({
    this.id = '',
    required this.umbrellaId,
    required this.clientName,
    required this.startDate,
    required this.endDate,
    this.notes = '',
    this.arrived = false,
    this.phone = '',
    this.price,
    this.deposit = 0,
    this.paid = false,
    this.updatedBy,
  });

  /// Converte una data salvata in formati diversi (Timestamp, stringa, millisecondi).
  static DateTime parseDate(dynamic d) {
    if (d == null) return DateTime(2000);
    if (d is Timestamp) return d.toDate();
    if (d is DateTime) return d;
    if (d is String) {
      final p = DateTime.tryParse(d);
      if (p != null) return p;
      try {
        final parts = d.split('/');
        if (parts.length == 3) return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      } catch (_) {
        // formato non riconosciuto: si usa il valore di ripiego sotto
      }
    }
    if (d is int) return DateTime.fromMillisecondsSinceEpoch(d);
    return DateTime(2000);
  }

  static double? _parseAmount(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  factory Booking.fromMap(String id, Map<String, dynamic> data) {
    return Booking(
      id: id,
      umbrellaId: (data['umbrellaId'] ?? data['id'] ?? id).toString(),
      clientName: (data['clientName'] ?? data['nome'] ?? data['cliente'] ?? data['name'] ?? 'Senza Nome').toString(),
      startDate: parseDate(data['startDate'] ?? data['start_date'] ?? data['dataInizio'] ?? data['data_inizio']),
      endDate: parseDate(data['endDate'] ?? data['end_date'] ?? data['dataFine'] ?? data['data_fine']),
      notes: (data['notes'] ?? data['note'] ?? '').toString(),
      arrived: data['arrived'] == true || data['arrivato'] == true,
      phone: (data['phone'] ?? data['telefono'] ?? '').toString(),
      price: _parseAmount(data['price']),
      deposit: _parseAmount(data['deposit']) ?? 0,
      paid: data['paid'] == true,
      updatedBy: data['updatedBy'] as String?,
    );
  }

  factory Booking.fromFirestore(DocumentSnapshot doc) =>
      Booking.fromMap(doc.id, (doc.data() as Map<String, dynamic>?) ?? const {});

  /// Dati nel formato standard usato dall'app (senza i campi di controllo
  /// createdAt/updatedAt/updatedBy, che aggiunge il BookingService).
  Map<String, dynamic> toFirestore() => {
        'umbrellaId': umbrellaId,
        'clientName': clientName,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'notes': notes,
        'arrived': arrived,
        'phone': phone,
        'price': price,
        'deposit': deposit,
        'paid': paid,
      };

  Booking copyWith({
    String? id,
    String? umbrellaId,
    String? clientName,
    DateTime? startDate,
    DateTime? endDate,
    String? notes,
    bool? arrived,
    String? phone,
    double? price,
    bool clearPrice = false,
    double? deposit,
    bool? paid,
  }) {
    return Booking(
      id: id ?? this.id,
      umbrellaId: umbrellaId ?? this.umbrellaId,
      clientName: clientName ?? this.clientName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      notes: notes ?? this.notes,
      arrived: arrived ?? this.arrived,
      phone: phone ?? this.phone,
      price: clearPrice ? null : (price ?? this.price),
      deposit: deposit ?? this.deposit,
      paid: paid ?? this.paid,
      updatedBy: updatedBy,
    );
  }

  DateTimeRange get range => DateTimeRange(start: dayOnly(startDate), end: dayOnly(endDate));

  /// Numero di giorni prenotati (primo e ultimo inclusi).
  int get days => daysBetween(startDate, endDate) + 1;

  /// true se la prenotazione occupa almeno un giorno dell'intervallo.
  bool overlaps(DateTimeRange r) =>
      !dayOnly(endDate).isBefore(dayOnly(r.start)) && !dayOnly(startDate).isAfter(dayOnly(r.end));

  /// true se la prenotazione occupa il giorno indicato.
  bool coversDay(DateTime day) {
    final d = dayOnly(day);
    return !dayOnly(startDate).isAfter(d) && !dayOnly(endDate).isBefore(d);
  }

  PaymentStatus get paymentStatus {
    if (paid) return PaymentStatus.paid;
    if (price == null || price == 0) return PaymentStatus.none;
    return PaymentStatus.due;
  }

  /// Quanto resta da incassare (0 se saldato o senza prezzo).
  double get amountDue {
    if (paid || price == null) return 0;
    final due = price! - deposit;
    return due > 0 ? due : 0;
  }

  /// Quanto è già stato incassato.
  double get amountCollected {
    if (paid) return price ?? deposit;
    return deposit;
  }

  /// Numero dell'ombrellone senza il settore (es. 'Mare-51' -> '51', 'Tende-T1-2' -> 'T1-2').
  String get umbrellaLabel => umbrellaLabelFromId(umbrellaId);

  /// Settore dall'ID (es. 'Mare-51' -> 'Mare').
  String get sectorName => umbrellaId.split('-').first;
}

/// Numero visibile dell'ombrellone partendo dall'ID completo.
String umbrellaLabelFromId(String id) {
  if (id.startsWith('Tende-')) return id.replaceFirst('Tende-', '');
  return id.contains('-') ? id.split('-').last : id;
}

class Umbrella {
  final String id;
  final String sectorName;
  final int index;
  Umbrella({required this.id, required this.sectorName, required this.index});

  String get simpleId => umbrellaLabelFromId(id);
}

class BeachSector {
  final String name;
  final List<Umbrella> umbrellas;
  final int crossAxisCount;
  final int rows;
  final List<int> walkwayColumns;
  BeachSector({required this.name, required this.umbrellas, required this.crossAxisCount, required this.rows, this.walkwayColumns = const []});

  /// Ordine fisso dei settori sulla mappa.
  static const sectorOrder = {'Mare': 1, 'Tende': 2, 'Dietro': 3};

  /// Legge un settore dal documento `beachLayout/{settore}`.
  factory BeachSector.fromMap(Map<String, dynamic> data) {
    final sectorName = data['name'] as String;
    final umbrellas = ((data['umbrellas'] as List<dynamic>?) ?? const [])
        .map((u) => Umbrella(id: '$sectorName-${u['id']}', sectorName: sectorName, index: (u['index'] as num).toInt()))
        .toList();
    return BeachSector(
      name: sectorName,
      rows: (data['rows'] as num?)?.toInt() ?? 1,
      crossAxisCount: (data['crossAxisCount'] as num?)?.toInt() ?? 1,
      umbrellas: umbrellas,
      walkwayColumns: ((data['walkwayColumns'] as List<dynamic>?) ?? const []).map((e) => (e as num).toInt()).toList(),
    );
  }

  static List<BeachSector> sorted(Iterable<BeachSector> sectors) =>
      sectors.toList()..sort((a, b) => (sectorOrder[a.name] ?? 99).compareTo(sectorOrder[b.name] ?? 99));
}
