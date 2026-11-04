import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

/// Unico punto di lettura delle prenotazioni.
///
/// Tiene aperto UN SOLO listener Firestore per tutta l'app: Mappa, Arrivi,
/// Statistiche e Ricerca leggono da qui invece di scaricare ogni volta tutte
/// le prenotazioni. Così si pagano solo le letture iniziali e poi solo i
/// documenti che cambiano, restando lontani dal limite gratuito giornaliero.
class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore, DateTime Function()? clock})
      : _firestore = firestore,
        _now = clock ?? DateTime.now;

  static BookingRepository? _instance;
  static BookingRepository get instance => _instance ??= BookingRepository();
  @visibleForTesting
  static set instance(BookingRepository repository) => _instance = repository;

  /// Versione del formato dati. Alla 2 tutte le prenotazioni hanno
  /// startDate/endDate come Timestamp, quindi si possono filtrare per data.
  static const int schemaVersion = 2;

  /// Firestore accetta al massimo 500 operazioni per batch.
  static const int maxBatch = 400;

  final FirebaseFirestore? _firestore;
  final DateTime Function() _now;

  FirebaseFirestore get db => _firestore ?? FirebaseFirestore.instance;

  final ValueNotifier<List<Booking>?> bookings = ValueNotifier(null);
  final ValueNotifier<Object?> error = ValueNotifier(null);

  /// Messaggio per l'admin se la conversione dei dati vecchi non è riuscita (null = tutto bene).
  final ValueNotifier<String?> migrationProblem = ValueNotifier(null);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// Ogni avvio ha un numero: se nel frattempo ne parte un altro, il vecchio si ferma
  /// (così non restano mai due collegamenti aperti insieme).
  int _generation = 0;

  CollectionReference<Map<String, dynamic>> get collection => db.collection('bookings');
  DocumentReference<Map<String, dynamic>> get _schemaDoc => db.collection('meta').doc('schema');

  /// Si caricano solo le prenotazioni che finiscono da inizio anno in poi:
  /// le stagioni passate non vengono più lette.
  DateTime get windowStart => DateTime(_now().year, 1, 1);

  /// Data di oggi (a mezzanotte). Unica fonte di "oggi" per tutte le schermate.
  DateTime get today => dayOnly(_now());

  bool get isStarted => _sub != null;

  Future<void> start({required bool isAdmin}) async {
    final generation = ++_generation;
    await _cancel();
    int version = 0;
    var versionFromServer = false;
    try {
      final meta = await _schemaDoc.get(const GetOptions(source: Source.server));
      version = (meta.data()?['version'] as num?)?.toInt() ?? 0;
      versionFromServer = true;
    } catch (e) {
      debugPrint('Versione schema non letta dal server ($e), provo la copia sul telefono.');
      try {
        final cached = await _schemaDoc.get(const GetOptions(source: Source.cache));
        version = (cached.data()?['version'] as num?)?.toInt() ?? 0;
      } catch (_) {
        // nessuna copia: si legge tutta la collezione, così non sparisce nulla
      }
    }
    if (generation != _generation) return;

    // Si converte solo se il SERVER dice che serve (mai offline: le scritture resterebbero appese).
    if (version < schemaVersion && isAdmin && versionFromServer) {
      try {
        await migrateToSchema2();
        version = schemaVersion;
        migrationProblem.value = null;
      } catch (e) {
        debugPrint('Migrazione prenotazioni fallita: $e');
        migrationProblem.value = 'Non sono riuscito a convertire le prenotazioni vecchie ($e). '
            'L\'app funziona lo stesso; riprova riaprendola con la connessione.';
      }
    }
    if (generation != _generation) return;

    // Finché i dati vecchi non sono stati convertiti si legge tutta la
    // collezione (ma sempre con un solo listener), così non sparisce nulla.
    final Query<Map<String, dynamic>> query = version >= schemaVersion
        ? collection.where('endDate', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        : collection;

    _sub = query.snapshots().listen(
      (snap) {
        bookings.value = List.unmodifiable(snap.docs.map(Booking.fromFirestore));
        error.value = null;
      },
      onError: (Object e) => error.value = e,
    );
  }

  Future<void> stop() async {
    _generation++;
    await _cancel();
  }

  Future<void> _cancel() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    bookings.value = null;
    error.value = null;
  }

  /// Converte una volta sola le prenotazioni salvate in formati vecchi
  /// (date come stringa, campi con altri nomi) nel formato standard.
  /// Restituisce quante prenotazioni sono state corrette.
  Future<int> migrateToSchema2() async {
    final snap = await collection.get();
    final toFix = <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};
    const standardKeys = {
      'umbrellaId', 'clientName', 'startDate', 'endDate', 'notes', 'arrived',
      'phone', 'price', 'deposit', 'paid', 'createdAt', 'updatedAt', 'updatedBy',
    };
    for (final doc in snap.docs) {
      final data = doc.data();
      final isStandard = data['startDate'] is Timestamp &&
          data['endDate'] is Timestamp &&
          data['umbrellaId'] is String &&
          data['clientName'] is String &&
          data.keys.every(standardKeys.contains);
      if (isStandard) continue;
      final b = sanitizeLegacy(Booking.fromFirestore(doc));
      // set senza merge: elimina i vecchi campi con nomi diversi
      toFix[doc.reference] = {...b.toFirestore(), 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': 'migrazione'};
    }
    final entries = toFix.entries.toList();
    for (var i = 0; i < entries.length; i += maxBatch) {
      final batch = db.batch();
      for (final e in entries.skip(i).take(maxBatch)) {
        batch.set(e.key, e.value);
      }
      await batch.commit();
    }
    await _schemaDoc.set({'version': schemaVersion, 'migratedAt': FieldValue.serverTimestamp()});
    return entries.length;
  }

  /// Ripulisce una prenotazione vecchia perché rispetti le regole di sicurezza
  /// (altrimenti un solo valore fuori misura farebbe fallire tutta la conversione).
  static Booking sanitizeLegacy(Booking b) {
    String cut(String v, int max) => v.length > max ? v.substring(0, max) : v;
    final name = b.clientName.trim().isEmpty ? 'Senza nome' : cut(b.clientName.trim(), 100);
    final umbrella = cut(b.umbrellaId.trim(), 40);
    final price = (b.price != null && b.price! >= 0 && b.price! < 1000000) ? b.price : null;
    final deposit = (b.deposit >= 0 && b.deposit < 1000000) ? b.deposit : 0.0;
    final start = dayOnly(b.startDate);
    var end = dayOnly(b.endDate);
    if (end.isBefore(start)) end = start;
    return Booking(
      id: b.id,
      umbrellaId: umbrella.isEmpty ? 'Senza-ombrellone' : umbrella,
      clientName: name,
      startDate: start,
      endDate: end,
      notes: cut(b.notes, 500),
      arrived: b.arrived,
      phone: cut(b.phone.trim(), 30),
      price: price,
      deposit: deposit,
      paid: b.paid,
    );
  }

  /// Reset di fine stagione: cancella le prenotazioni già finite (prima di oggi).
  /// Quelle future (es. già inserite per l'anno dopo) restano, a meno di [includeFuture].
  Future<int> deleteSeason({bool includeFuture = false}) async {
    if (includeFuture) return deleteAllBookings();
    final snap = await collection.where('endDate', isLessThan: Timestamp.fromDate(today)).get();
    await deleteInChunks(snap.docs.map((d) => d.reference).toList());
    return snap.docs.length;
  }

  /// Cancella TUTTE le prenotazioni (anche quelle delle stagioni passate).
  Future<int> deleteAllBookings() async {
    final snap = await collection.get();
    await deleteInChunks(snap.docs.map((d) => d.reference).toList());
    return snap.docs.length;
  }

  /// Cancella i documenti a blocchi, rispettando il limite di Firestore.
  Future<void> deleteInChunks(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += maxBatch) {
      final batch = db.batch();
      for (final ref in refs.skip(i).take(maxBatch)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }
}
