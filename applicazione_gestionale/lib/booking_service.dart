import 'dart:async';

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

/// Senza connessione non si può controllare sul server che l'ombrellone sia libero:
/// meglio non salvare che rischiare una doppia prenotazione.
class BookingOfflineException extends BookingValidationException {
  const BookingOfflineException()
      : super('Nessuna connessione a internet: non posso controllare che l\'ombrellone sia libero. Riprova quando c\'è campo.');
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

  /// Solo per i test: simula l'assenza di connessione.
  @visibleForTesting
  bool debugOffline = false;

  /// Le scritture aspettano la conferma del server al massimo così: se la connessione
  /// cade, Firestore le tiene in coda e le invia da solo appena torna il campo.
  static const Duration writeTimeout = Duration(seconds: 10);

  Future<void> _write(Future<void> operation) async {
    try {
      await operation.timeout(writeTimeout);
    } on TimeoutException {
      debugPrint('Scrittura in coda: verrà inviata appena torna la connessione.');
    }
  }

  /// Prenotazioni di un ombrellone lette dal server (dati più aggiornati).
  /// Senza connessione si rifiuta: meglio non salvare che rischiare una doppia prenotazione.
  Future<List<Booking>> _bookingsOfUmbrella(String umbrellaId) async {
    if (debugOffline) throw const BookingOfflineException();
    try {
      final snap = await _col.where('umbrellaId', isEqualTo: umbrellaId).get(const GetOptions(source: Source.server));
      return snap.docs.map(Booking.fromFirestore).toList();
    } catch (e) {
      debugPrint('Controllo sul server non riuscito: $e');
      throw const BookingOfflineException();
    }
  }

  /// true se la prenotazione esiste ancora sul server (un altro telefono potrebbe averla eliminata).
  Future<bool> _existsOnServer(String id) async {
    if (debugOffline) throw const BookingOfflineException();
    try {
      return (await _col.doc(id).get(const GetOptions(source: Source.server))).exists;
    } catch (e) {
      debugPrint('Controllo sul server non riuscito: $e');
      throw const BookingOfflineException();
    }
  }

  Future<void> ensureAvailable(Booking b) async {
    final conflict = findConflict(b, await _bookingsOfUmbrella(b.umbrellaId));
    if (conflict != null) throw BookingConflictException(conflict);
  }

  /// Campi che non si scrivono mai "in blocco": si cambiano con le loro azioni
  /// (spunta arrivo, saldato) o solo se la scheda li ha davvero modificati.
  static const _statusFields = {'arrived', 'paid'};

  /// Solo i campi cambiati rispetto a come era la prenotazione quando è stata aperta.
  /// Così una scheda aperta da tempo non annulla quello che un altro telefono ha fatto nel frattempo.
  static Map<String, dynamic> changedFields(Booking original, Booking edited) {
    final before = original.copyWith(startDate: dayOnly(original.startDate), endDate: dayOnly(original.endDate)).toFirestore();
    final after = edited.toFirestore();
    return {
      for (final e in after.entries)
        if (before[e.key] != e.value) e.key: e.value,
    };
  }

  /// Crea o aggiorna una prenotazione. Restituisce l'ID del documento.
  ///
  /// Per una modifica, [original] è la prenotazione com'era quando la scheda è stata aperta:
  /// si scrivono solo i campi cambiati. Se la prenotazione nel frattempo è stata eliminata
  /// da un altro telefono, non viene ricreata.
  Future<String> save(Booking booking, {Booking? original}) async {
    final b = validate(booking);
    await ensureAvailable(b);
    if (b.id.isEmpty) {
      final ref = _col.doc();
      await _write(ref.set({...b.toFirestore(), ..._audit(create: true)}));
      return ref.id;
    }
    if (!await _existsOnServer(b.id)) {
      throw const BookingValidationException('Questa prenotazione è stata eliminata da un altro telefono.');
    }
    final fields = original != null
        ? changedFields(original, b)
        : (b.toFirestore()..removeWhere((k, _) => _statusFields.contains(k)));
    if (fields.isEmpty) return b.id;
    await _write(_col.doc(b.id).update({...fields, ..._audit()}));
    return b.id;
  }

  /// Sposta la prenotazione su un altro ombrellone (e/o altre date).
  /// [original] è com'era la prenotazione prima delle modifiche fatte nella scheda (se ce ne sono).
  Future<void> move(Booking booking, String newUmbrellaId, DateTimeRange range, {Booking? original}) async {
    await save(booking.copyWith(umbrellaId: newUmbrellaId, startDate: range.start, endDate: range.end), original: original ?? booking);
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

  Future<void> setArrived(Booking b, bool arrived) => _write(_col.doc(b.id).update({'arrived': arrived, ..._audit()}));

  Future<void> setPaid(Booking b, bool paid) => _write(_col.doc(b.id).update({'paid': paid, ..._audit()}));

  Future<void> delete(Booking b) => _write(_col.doc(b.id).delete());

  /// Ripristina una prenotazione appena eliminata (tasto "Annulla").
  Future<void> restore(Booking b) async {
    final clean = validate(b);
    await ensureAvailable(clean);
    await _write(_col.doc(b.id).set({...clean.toFirestore(), ..._audit(create: true)}));
  }
}
