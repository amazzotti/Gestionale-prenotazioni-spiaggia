import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/models.dart';

Map<String, dynamic> bookingData(String umbrella, DateTime start, DateTime end, {String name = 'Cliente'}) => {
      'umbrellaId': umbrella,
      'clientName': name,
      'startDate': Timestamp.fromDate(start),
      'endDate': Timestamp.fromDate(end),
      'notes': '',
      'arrived': false,
    };

/// Aspetta che il listener del repository riceva i dati.
Future<List<Booking>> firstBookings(BookingRepository repo) async {
  for (var i = 0; i < 50 && repo.bookings.value == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return repo.bookings.value!;
}

void main() {
  late FakeFirebaseFirestore db;
  late BookingRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = BookingRepository(firestore: db, clock: () => DateTime(2027, 7, 15));
  });

  tearDown(() => repo.stop());

  test('windowStart è il primo gennaio dell\'anno in corso', () {
    expect(repo.windowStart, DateTime(2027, 1, 1));
  });

  test('con lo schema aggiornato carica solo la stagione in corso', () async {
    await db.collection('meta').doc('schema').set({'version': BookingRepository.schemaVersion});
    await db.collection('bookings').add(bookingData('Mare-1', DateTime(2026, 7, 1), DateTime(2026, 7, 5), name: 'Vecchia'));
    await db.collection('bookings').add(bookingData('Mare-1', DateTime(2027, 7, 1), DateTime(2027, 7, 5), name: 'Nuova'));
    await db.collection('bookings').add(bookingData('Mare-2', DateTime(2026, 12, 28), DateTime(2027, 1, 3), name: 'A cavallo'));

    await repo.start(isAdmin: false);
    final list = await firstBookings(repo);
    expect(list.map((b) => b.clientName).toSet(), {'Nuova', 'A cavallo'});
    expect(repo.isStarted, isTrue);
  });

  test('senza migrazione (utente staff) legge tutto per non perdere dati', () async {
    await db.collection('bookings').add({'id': 'Mare-1', 'nome': 'Legacy', 'data_inizio': '01/07/2027', 'data_fine': '05/07/2027'});
    await repo.start(isAdmin: false);
    final list = await firstBookings(repo);
    expect(list.single.clientName, 'Legacy');
    expect((await db.collection('meta').doc('schema').get()).exists, isFalse);
  });

  test('l\'admin converte i dati vecchi al primo accesso', () async {
    final legacy = await db.collection('bookings').add({
      'id': 'Mare-3',
      'nome': 'Legacy',
      'data_inizio': '10/07/2027',
      'data_fine': '05/07/2027', // fine prima dell'inizio: va corretta
      'arrivato': true,
    });
    final good = await db.collection('bookings').add(bookingData('Mare-1', DateTime(2027, 7, 1), DateTime(2027, 7, 5)));

    await repo.start(isAdmin: true);
    await firstBookings(repo);

    final fixed = (await legacy.get()).data()!;
    expect(fixed['umbrellaId'], 'Mare-3');
    expect(fixed['clientName'], 'Legacy');
    expect(fixed['startDate'], isA<Timestamp>());
    expect((fixed['endDate'] as Timestamp).toDate(), DateTime(2027, 7, 10));
    expect(fixed['arrived'], isTrue);
    expect(fixed.containsKey('nome'), isFalse, reason: 'i vecchi campi vengono eliminati');
    expect(fixed['updatedBy'], 'migrazione');

    final untouched = (await good.get()).data()!;
    expect(untouched.containsKey('updatedBy'), isFalse, reason: 'i documenti già corretti non vengono riscritti');

    final meta = (await db.collection('meta').doc('schema').get()).data()!;
    expect(meta['version'], BookingRepository.schemaVersion);
  });

  test('migrateToSchema2 restituisce quante prenotazioni ha corretto', () async {
    await db.collection('bookings').add({'nome': 'A', 'data_inizio': '01/07/2027', 'data_fine': '02/07/2027'});
    await db.collection('bookings').add(bookingData('Mare-1', DateTime(2027, 7, 1), DateTime(2027, 7, 5)));
    expect(await repo.migrateToSchema2(), 1);
    expect(await repo.migrateToSchema2(), 0);
  });

  test('deleteAllBookings funziona anche oltre il limite di 500 operazioni', () async {
    for (var i = 0; i < 520; i++) {
      await db.collection('bookings').add(bookingData('Mare-$i', DateTime(2027, 7, 1), DateTime(2027, 7, 2)));
    }
    expect(await repo.deleteAllBookings(), 520);
    expect((await db.collection('bookings').get()).docs, isEmpty);
  });

  test('stop svuota i dati in memoria', () async {
    await repo.start(isAdmin: false);
    await firstBookings(repo);
    await repo.stop();
    expect(repo.bookings.value, isNull);
    expect(repo.isStarted, isFalse);
  });
}
