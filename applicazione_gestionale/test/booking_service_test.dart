import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/models.dart';

Booking newBooking({
  String umbrella = 'Mare-1',
  String name = 'Rossi',
  DateTime? start,
  DateTime? end,
  double? price,
  double deposit = 0,
}) =>
    Booking(
      umbrellaId: umbrella,
      clientName: name,
      startDate: start ?? DateTime(2027, 7, 1),
      endDate: end ?? DateTime(2027, 7, 5),
      price: price,
      deposit: deposit,
    );

void main() {
  late FakeFirebaseFirestore db;
  late BookingService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    final repo = BookingRepository(firestore: db, clock: () => DateTime(2027, 7, 1));
    service = BookingService(repository: repo, currentUserEmail: () => 'mamma@test.it');
  });

  Future<Map<String, dynamic>> docData(String id) async => (await db.collection('bookings').doc(id).get()).data()!;

  group('save', () {
    test('crea la prenotazione con i dati di controllo', () async {
      final id = await service.save(newBooking(name: '  Rossi  ', price: 100, deposit: 20));
      final data = await docData(id);
      expect(data['clientName'], 'Rossi', reason: 'gli spazi vengono tolti');
      expect(data['umbrellaId'], 'Mare-1');
      expect(data['price'], 100);
      expect(data['deposit'], 20);
      expect(data['updatedBy'], 'mamma@test.it');
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['updatedAt'], isA<Timestamp>());
    });

    test('salva le date a mezzanotte', () async {
      final id = await service.save(newBooking(start: DateTime(2027, 7, 1, 15, 30), end: DateTime(2027, 7, 2, 9)));
      final data = await docData(id);
      expect((data['startDate'] as Timestamp).toDate(), DateTime(2027, 7, 1));
      expect((data['endDate'] as Timestamp).toDate(), DateTime(2027, 7, 2));
    });

    test('rifiuta un ombrellone già occupato', () async {
      await service.save(newBooking(name: 'Primo'));
      expect(
        () => service.save(newBooking(name: 'Secondo', start: DateTime(2027, 7, 5), end: DateTime(2027, 7, 8))),
        throwsA(isA<BookingConflictException>().having((e) => e.conflict.clientName, 'cliente', 'Primo')),
      );
    });

    test('permette giorni adiacenti e altri ombrelloni', () async {
      await service.save(newBooking());
      await service.save(newBooking(start: DateTime(2027, 7, 6), end: DateTime(2027, 7, 8)));
      await service.save(newBooking(umbrella: 'Mare-2'));
      expect((await db.collection('bookings').get()).docs.length, 3);
    });

    test('la modifica non va in conflitto con se stessa e mantiene createdAt', () async {
      final id = await service.save(newBooking());
      final createdAt = (await docData(id))['createdAt'];
      await service.save(newBooking(end: DateTime(2027, 7, 10)).copyWith(id: id, clientName: 'Rossi Mario'));
      final data = await docData(id);
      expect(data['clientName'], 'Rossi Mario');
      expect((data['endDate'] as Timestamp).toDate(), DateTime(2027, 7, 10));
      expect(data['createdAt'], createdAt);
    });

    test('controlla i dati', () async {
      Future<void> expectInvalid(Booking b) => expectLater(service.save(b), throwsA(isA<BookingValidationException>()));
      await expectInvalid(newBooking(name: '   '));
      await expectInvalid(newBooking(name: 'x' * 101));
      await expectInvalid(newBooking(start: DateTime(2027, 7, 5), end: DateTime(2027, 7, 1)));
      await expectInvalid(newBooking(price: -1));
      await expectInvalid(newBooking(price: 50, deposit: 60));
      await expectInvalid(newBooking().copyWith(notes: 'n' * 501));
      await expectInvalid(newBooking(umbrella: ' '));
      expect((await db.collection('bookings').get()).docs, isEmpty);
    });
  });

  test('move sposta su un ombrellone libero e rifiuta uno occupato', () async {
    final id = await service.save(newBooking());
    await service.save(newBooking(umbrella: 'Mare-3', name: 'Altro'));
    final booking = Booking.fromMap(id, await docData(id));

    await service.move(booking, 'Mare-2', DateTimeRange(start: DateTime(2027, 7, 2), end: DateTime(2027, 7, 6)));
    final moved = await docData(id);
    expect(moved['umbrellaId'], 'Mare-2');
    expect((moved['startDate'] as Timestamp).toDate(), DateTime(2027, 7, 2));

    expect(
      () => service.move(booking, 'Mare-3', booking.range),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('createExtension copia nome, telefono e note sui giorni extra', () async {
    final original = newBooking().copyWith(phone: '3331234567', notes: 'vicino al bar', price: 100);
    final id = await service.createExtension(original, 'Mare-4', DateTimeRange(start: DateTime(2027, 7, 6), end: DateTime(2027, 7, 8)));
    final data = await docData(id);
    expect(data['umbrellaId'], 'Mare-4');
    expect(data['clientName'], 'Rossi');
    expect(data['phone'], '3331234567');
    expect(data['notes'], 'vicino al bar');
    expect(data['price'], isNull, reason: 'il prezzo dei giorni extra si decide a parte');
  });

  test('setArrived e setPaid aggiornano anche chi ha modificato', () async {
    final id = await service.save(newBooking(price: 80));
    final b = Booking.fromMap(id, await docData(id));
    await service.setArrived(b, true);
    await service.setPaid(b, true);
    final data = await docData(id);
    expect(data['arrived'], isTrue);
    expect(data['paid'], isTrue);
    expect(data['updatedBy'], 'mamma@test.it');
  });

  group('delete e restore', () {
    test('ripristina con lo stesso ID', () async {
      final id = await service.save(newBooking(price: 50));
      final b = Booking.fromMap(id, await docData(id));
      await service.delete(b);
      expect((await db.collection('bookings').doc(id).get()).exists, isFalse);

      await service.restore(b);
      final data = await docData(id);
      expect(data['clientName'], 'Rossi');
      expect(data['price'], 50);
    });

    test('non ripristina se nel frattempo il posto è stato preso', () async {
      final id = await service.save(newBooking());
      final b = Booking.fromMap(id, await docData(id));
      await service.delete(b);
      await service.save(newBooking(name: 'Nuovo cliente'));
      expect(() => service.restore(b), throwsA(isA<BookingConflictException>()));
    });
  });
}
