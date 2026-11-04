import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'availability.dart';
import 'booking_repository.dart';
import 'device_service.dart';
import 'models.dart';

/// L'ombrellone è già occupato nel periodo richiesto.
class BookingConflictException implements Exception {
  final Booking conflict;
  const BookingConflictException(this.conflict);
  @override
  String toString() => 'Ombrellone occupato da ${conflict.clientName}';
}

/// Dati della prenotazione non validi (messaggio già in italiano).
class BookingValidationException implements Exception {
  final String message;
  const BookingValidationException(this.message);
  @override
  String toString() => message;
}

/// Tutte le scritture sulle prenotazioni passano da qui:
/// - controlla i dati prima di salvarli;
/// - ricontrolla sul server che l'ombrellone sia libero, così due telefoni
///   non possono prenotare lo stesso posto negli stessi giorni;
/// - registra chi ha fatto l'ultima modifica e quando.
class BookingService {
  BookingService({BookingRepository? repository, String? Function()? currentUserName})
      : _repository = repository,
        _currentUserName = currentUserName;

  static BookingService? _instance;
  static BookingService get instance => _instance ??= BookingService();
  @visibleForTesting
  static set instance(BookingService service) => _instance = service;

  final BookingRepository? _repository;
  final String? Function()? _currentUserName;

  BookingRepository get repository => _repository ?? BookingRepository.instance;
  CollectionReference<Map<String, dynamic>> get _col => repository.collection;

  /// Chi sta modificando: il nome del telefono (es. "Telefono di mamma").
  String get _userName {
    if (_currentUserName != null) return _currentUserName() ?? '';
    return DeviceService.instance.currentDeviceName ?? '';
  }

  Map<String, dynamic> _audit({bool create = false}) => {
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _userName,
        if (create) 'createdAt': FieldValue.serverTimestamp(),
      };

  static const int maxNameLength = 100;
  static const int maxNotesLength = 500;
  static const int maxPhoneLength = 30;

  /// Controlla i dati e restituisce la prenotazione "ripulita".
  static Booking validate(Booking b) {
    final name = b.clientName.trim();
    if (name.isEmpty) throw const BookingValidationException('Inserisci il nome del cliente.');
    if (name.length > maxNameLength) throw const BookingValidationException('Il nome è troppo lungo.');
    if (b.umbrellaId.trim().isEmpty) throw const BookingValidationException('Ombrellone non valido.');
    if (dayOnly(b.endDate).isBefore(dayOnly(b.startDate))) {
      throw const BookingValidationException('La data di fine è prima della data di inizio.');
    }
    if (b.notes.length > maxNotesLength) throw const BookingValidationException('Le note sono troppo lunghe.');
    final phone = b.phone.trim();
    if (phone.length > maxPhoneLength) throw const BookingValidationException('Numero di telefono non valido.');
    if ((b.price ?? 0) < 0 || b.deposit < 0) throw const BookingValidationException('Gli importi non possono essere negativi.');
    if (b.price != null && b.deposit > b.price!) {
      throw const BookingValidationException('L\'acconto è più alto del prezzo.');
    }
    return b.copyWith(
      clientName: name,
      phone: phone,
      notes: b.notes.trim(),
      startDate: dayOnly(b.startDate),
      endDate: dayOnly(b.endDate),
    );
  }

  /// Prenotazioni di un ombrellone lette dal server (dati più aggiornati).
  /// Senza connessione si usano quelle in memoria.
  Future<List<Booking>> _bookingsOfUmbrella(String umbrellaId) async {
    try {
      final snap = await _col.where('umbrellaId', isEqualTo: umbrellaId).get(const GetOptions(source: Source.server));
      return snap.docs.map(Booking.fromFirestore).toList();
    } catch (e) {
      debugPrint('Controllo sul server non riuscito, uso i dati in memoria: $e');
      return (repository.bookings.value ?? const <Booking>[]).where((b) => b.umbrellaId == umbrellaId).toList();
    }
  }

  Future<void> ensureAvailable(Booking b) async {
    final conflict = findConflict(b, await _bookingsOfUmbrella(b.umbrellaId));
    if (conflict != null) throw BookingConflictException(conflict);
  }

  /// Crea o aggiorna una prenotazione. Restituisce l'ID del documento.
  Future<String> save(Booking booking) async {
    final b = validate(booking);
    await ensureAvailable(b);
    if (b.id.isEmpty) {
      final ref = await _col.add({...b.toFirestore(), ..._audit(create: true)});
      return ref.id;
    }
    await _col.doc(b.id).set({...b.toFirestore(), ..._audit()}, SetOptions(merge: true));
    return b.id;
  }

  /// Sposta la prenotazione su un altro ombrellone (e/o altre date).
  Future<void> move(Booking booking, String newUmbrellaId, DateTimeRange range) async {
    await save(booking.copyWith(umbrellaId: newUmbrellaId, startDate: range.start, endDate: range.end));
  }

  /// Crea i giorni extra di una prenotazione su un altro ombrellone.
  Future<String> createExtension(Booking original, String umbrellaId, DateTimeRange extra) {
    return save(Booking(
      umbrellaId: umbrellaId,
      clientName: original.clientName,
      phone: original.phone,
      notes: original.notes,
      startDate: extra.start,
      endDate: extra.end,
    ));
  }

  Future<void> setArrived(Booking b, bool arrived) => _col.doc(b.id).update({'arrived': arrived, ..._audit()});

  Future<void> setPaid(Booking b, bool paid) => _col.doc(b.id).update({'paid': paid, ..._audit()});

  Future<void> delete(Booking b) => _col.doc(b.id).delete();

  /// Ripristina una prenotazione appena eliminata (tasto "Annulla").
  Future<void> restore(Booking b) async {
    final clean = validate(b);
    await ensureAvailable(clean);
    await _col.doc(b.id).set({...clean.toFirestore(), ..._audit(create: true)});
  }
}
