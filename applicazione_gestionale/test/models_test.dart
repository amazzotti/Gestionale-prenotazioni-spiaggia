import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicazione_gestionale/models.dart';

Booking booking(DateTime start, DateTime end, {double? price, double deposit = 0, bool paid = false}) => Booking(
      id: 'x',
      umbrellaId: 'Mare-1',
      clientName: 'Rossi',
      startDate: start,
      endDate: end,
      price: price,
      deposit: deposit,
      paid: paid,
    );

void main() {
  group('Booking.overlaps', () {
    final b = booking(DateTime(2027, 7, 10), DateTime(2027, 7, 20));

    test('periodo dentro la prenotazione', () {
      expect(b.overlaps(DateTimeRange(start: DateTime(2027, 7, 12), end: DateTime(2027, 7, 14))), isTrue);
    });

    test('tocca solo il primo o l\'ultimo giorno', () {
      expect(b.overlaps(DateTimeRange(start: DateTime(2027, 7, 1), end: DateTime(2027, 7, 10))), isTrue);
      expect(b.overlaps(DateTimeRange(start: DateTime(2027, 7, 20), end: DateTime(2027, 7, 25))), isTrue);
    });

    test('periodo prima o dopo', () {
      expect(b.overlaps(DateTimeRange(start: DateTime(2027, 7, 1), end: DateTime(2027, 7, 9))), isFalse);
      expect(b.overlaps(DateTimeRange(start: DateTime(2027, 7, 21), end: DateTime(2027, 7, 30))), isFalse);
    });

    test('ignora l\'ora salvata nella data', () {
      final withTime = booking(DateTime(2027, 7, 10, 18, 30), DateTime(2027, 7, 20, 9));
      expect(withTime.overlaps(DateTimeRange(start: DateTime(2027, 7, 20), end: DateTime(2027, 7, 20))), isTrue);
    });
  });

  test('coversDay include primo e ultimo giorno, anche con orario', () {
    final b = booking(DateTime(2027, 8, 1), DateTime(2027, 8, 3));
    expect(b.coversDay(DateTime(2027, 7, 31)), isFalse);
    expect(b.coversDay(DateTime(2027, 8, 1)), isTrue);
    expect(b.coversDay(DateTime(2027, 8, 3, 23, 59)), isTrue);
    expect(b.coversDay(DateTime(2027, 8, 4)), isFalse);
  });

  test('days conta primo e ultimo giorno', () {
    expect(booking(DateTime(2027, 8, 1), DateTime(2027, 8, 1)).days, 1);
    expect(booking(DateTime(2027, 8, 1), DateTime(2027, 8, 10)).days, 10);
  });

  group('pagamenti', () {
    test('senza prezzo', () {
      final b = booking(DateTime(2027, 8, 1), DateTime(2027, 8, 2));
      expect(b.paymentStatus, PaymentStatus.none);
      expect(b.amountDue, 0);
      expect(b.amountCollected, 0);
    });

    test('con acconto', () {
      final b = booking(DateTime(2027, 8, 1), DateTime(2027, 8, 2), price: 100, deposit: 30);
      expect(b.paymentStatus, PaymentStatus.due);
      expect(b.amountDue, 70);
      expect(b.amountCollected, 30);
    });

    test('saldato', () {
      final b = booking(DateTime(2027, 8, 1), DateTime(2027, 8, 2), price: 100, deposit: 30, paid: true);
      expect(b.paymentStatus, PaymentStatus.paid);
      expect(b.amountDue, 0);
      expect(b.amountCollected, 100);
    });

    test('acconto più alto del prezzo non dà importi negativi', () {
      final b = booking(DateTime(2027, 8, 1), DateTime(2027, 8, 2), price: 50, deposit: 80);
      expect(b.amountDue, 0);
    });
  });

  group('Booking.parseDate (dati vecchi)', () {
    test('Timestamp', () => expect(Booking.parseDate(Timestamp.fromDate(DateTime(2027, 6, 1))), DateTime(2027, 6, 1)));
    test('stringa ISO', () => expect(Booking.parseDate('2027-06-01'), DateTime(2027, 6, 1)));
    test('stringa gg/mm/aaaa', () => expect(Booking.parseDate('01/06/2027'), DateTime(2027, 6, 1)));
    test('stringa non valida', () => expect(Booking.parseDate('ciao'), DateTime(2000)));
    test('valore mancante', () => expect(Booking.parseDate(null), DateTime(2000)));
  });

  test('fromMap legge i nomi dei campi vecchi', () {
    final b = Booking.fromMap('abc', {
      'id': 'Mare-7',
      'nome': 'Bianchi',
      'data_inizio': '01/07/2027',
      'data_fine': '2027-07-03',
      'note': 'lettino extra',
      'arrivato': true,
      'telefono': '333 1234567',
      'price': '120,50',
    });
    expect(b.id, 'abc');
    expect(b.umbrellaId, 'Mare-7');
    expect(b.clientName, 'Bianchi');
    expect(b.startDate, DateTime(2027, 7, 1));
    expect(b.endDate, DateTime(2027, 7, 3));
    expect(b.notes, 'lettino extra');
    expect(b.arrived, isTrue);
    expect(b.phone, '333 1234567');
    expect(b.price, 120.5);
  });

  test('toFirestore salva le date come Timestamp e tutti i campi', () {
    final data = booking(DateTime(2027, 7, 1), DateTime(2027, 7, 5), price: 90, deposit: 10).toFirestore();
    expect(data['startDate'], isA<Timestamp>());
    expect(data['endDate'], isA<Timestamp>());
    expect(data['umbrellaId'], 'Mare-1');
    expect(data['price'], 90);
    expect(data['deposit'], 10);
    expect(data.containsKey('id'), isFalse);
  });

  test('copyWith può togliere il prezzo', () {
    final b = booking(DateTime(2027, 7, 1), DateTime(2027, 7, 5), price: 90);
    expect(b.copyWith(clearPrice: true).price, isNull);
    expect(b.copyWith(clientName: 'Verdi').price, 90);
  });

  test('etichette ombrellone e settore', () {
    expect(umbrellaLabelFromId('Mare-51'), '51');
    expect(umbrellaLabelFromId('Tende-T1-2'), 'T1-2');
    expect(umbrellaLabelFromId('42'), '42');
    expect(Booking(umbrellaId: 'Dietro-3', clientName: 'x', startDate: DateTime(2027), endDate: DateTime(2027)).sectorName, 'Dietro');
  });

  group('BeachSector', () {
    test('fromMap costruisce gli ID completi', () {
      final s = BeachSector.fromMap({
        'name': 'Tende',
        'rows': 2,
        'crossAxisCount': 3,
        'umbrellas': [
          {'id': 'T1-1', 'index': 0},
          {'id': 'T2-1', 'index': 3},
        ],
        'walkwayColumns': [1],
      });
      expect(s.umbrellas.map((u) => u.id), ['Tende-T1-1', 'Tende-T2-1']);
      expect(s.umbrellas.first.simpleId, 'T1-1');
      expect(s.walkwayColumns, [1]);
    });

    test('sorted mette i settori nell\'ordine Mare, Tende, Dietro', () {
      BeachSector s(String n) => BeachSector(name: n, umbrellas: const [], crossAxisCount: 1, rows: 1);
      expect(BeachSector.sorted([s('Dietro'), s('Altro'), s('Mare'), s('Tende')]).map((e) => e.name), ['Mare', 'Tende', 'Dietro', 'Altro']);
    });
  });
}
