import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:applicazione_gestionale/availability.dart';
import 'package:applicazione_gestionale/models.dart';

DateTime d(int month, int day) => DateTime(2027, month, day);
DateTimeRange r(DateTime a, DateTime b) => DateTimeRange(start: a, end: b);

Booking b(String id, String umbrella, DateTime start, DateTime end,
        {String name = 'Cliente', String phone = '', double? price, double deposit = 0, bool paid = false}) =>
    Booking(id: id, umbrellaId: umbrella, clientName: name, startDate: start, endDate: end, phone: phone, price: price, deposit: deposit, paid: paid);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  final all = [
    b('1', 'Mare-1', d(7, 1), d(7, 5), name: 'Rossi Mario', phone: '333 111 2222'),
    b('2', 'Mare-1', d(7, 10), d(7, 12), name: 'Bianchi'),
    b('3', 'Mare-2', d(7, 3), d(7, 20), name: 'Verdi', price: 300, deposit: 100),
    b('4', 'Tende-T1-1', d(7, 5), d(7, 5), name: 'rossi mario', price: 40, paid: true),
  ];

  group('bookingsInRange', () {
    test('solo l\'ombrellone richiesto e in ordine di data', () {
      final res = bookingsInRange('Mare-1', r(d(7, 1), d(7, 31)), all);
      expect(res.map((e) => e.id), ['1', '2']);
    });
    test('periodo nullo = nessuna prenotazione', () {
      expect(bookingsInRange('Mare-1', null, all), isEmpty);
    });
  });

  group('firstFreeStretch', () {
    test('tutto libero', () {
      final range = r(d(8, 1), d(8, 3));
      expect(firstFreeStretch(const [], range)!.start, d(8, 1));
    });

    test('trova il primo buco nel periodo', () {
      final range = r(d(7, 4), d(7, 11));
      final free = firstFreeStretch(bookingsInRange('Mare-1', range, all), range)!;
      expect(free.start, d(7, 6));
      expect(free.end, d(7, 9));
    });

    test('tutto occupato', () {
      final range = r(d(7, 5), d(7, 15));
      expect(firstFreeStretch(bookingsInRange('Mare-2', range, all), range), isNull);
    });

    test('attraversa il cambio dell\'ora legale senza saltare giorni', () {
      final range = r(DateTime(2027, 10, 30), DateTime(2027, 11, 1));
      final busy = [b('x', 'Mare-9', DateTime(2027, 10, 30), DateTime(2027, 10, 30))];
      final free = firstFreeStretch(busy, range)!;
      expect(free.start, DateTime(2027, 10, 31));
      expect(free.end, DateTime(2027, 11, 1));
    });
  });

  group('umbrellaTimeline: prima, nel periodo, dopo', () {
    final season = [
      b('p1', 'Mare-7', d(6, 20), d(6, 25), name: 'Molto prima'),
      b('p2', 'Mare-7', d(7, 1), d(7, 8), name: 'Prima'),
      b('n1', 'Mare-7', d(7, 10), d(7, 12), name: 'Nel periodo'),
      b('a1', 'Mare-7', d(7, 15), d(7, 20), name: 'Dopo'),
      b('a2', 'Mare-7', d(7, 25), d(7, 30), name: 'Molto dopo'),
      b('x', 'Mare-8', d(7, 9), d(7, 9), name: 'Altro ombrellone'),
    ];

    test('trova la precedente più vicina e la successiva più vicina', () {
      final t = umbrellaTimeline('Mare-7', r(d(7, 10), d(7, 13)), season);
      expect(t.previous?.clientName, 'Prima');
      expect(t.inPeriod.map((e) => e.clientName), ['Nel periodo']);
      expect(t.next?.clientName, 'Dopo');
      expect(t.freeDaysBefore, 1); // libero il 9
      expect(t.freeDaysAfter, 1); // libero il 14
    });

    test('periodo vuoto: mostra comunque prima e dopo', () {
      final t = umbrellaTimeline('Mare-7', r(d(7, 21), d(7, 23)), season);
      expect(t.inPeriod, isEmpty);
      expect(t.previous?.clientName, 'Dopo');
      expect(t.next?.clientName, 'Molto dopo');
      expect(t.freeDaysBefore, 0); // finisce il 20, periodo dal 21
      expect(t.freeDaysAfter, 1); // libero il 24
    });

    test('esclude la prenotazione che si sta modificando', () {
      final t = umbrellaTimeline('Mare-7', r(d(7, 10), d(7, 12)), season, excludeId: 'n1');
      expect(t.inPeriod, isEmpty);
    });

    test('nessuna prima o dopo', () {
      final t = umbrellaTimeline('Mare-8', r(d(7, 9), d(7, 9)), season);
      expect(t.previous, isNull);
      expect(t.next, isNull);
      expect(t.freeDaysBefore, isNull);
    });

    test('freeDaysBetween e freeDaysText', () {
      expect(freeDaysBetween(d(7, 8), d(7, 9)), 0);
      expect(freeDaysBetween(d(7, 8), d(7, 12)), 3);
      expect(freeDaysBetween(DateTime(2027, 10, 30), DateTime(2027, 11, 2)), 2, reason: 'ora legale');
      expect(freeDaysText(0), 'subito');
      expect(freeDaysText(1), '1 giorno libero');
      expect(freeDaysText(4), '4 giorni liberi');
    });
  });

  group('findConflict', () {
    test('trova la sovrapposizione sullo stesso ombrellone', () {
      final c = findConflict(b('', 'Mare-1', d(7, 4), d(7, 8)), all);
      expect(c?.id, '1');
    });
    test('nessun conflitto su un altro ombrellone', () {
      expect(findConflict(b('', 'Mare-5', d(7, 4), d(7, 8)), all), isNull);
    });
    test('non va in conflitto con se stessa quando si modifica', () {
      expect(findConflict(b('1', 'Mare-1', d(7, 1), d(7, 8)), all), isNull);
    });
    test('giorni adiacenti non sono un conflitto', () {
      expect(findConflict(b('', 'Mare-1', d(7, 6), d(7, 9)), all), isNull);
    });
  });

  test('arrivi e partenze del giorno, in ordine alfabetico', () {
    expect(arrivalsOn(d(7, 5), all).map((e) => e.id), ['4']);
    expect(departuresOn(d(7, 5), all).map((e) => e.id), ['1', '4']);
    expect(arrivalsOn(DateTime(2027, 7, 3, 15), all).map((e) => e.id), ['3']);
  });

  group('searchBookings', () {
    test('per nome senza distinguere maiuscole', () {
      expect(searchBookings('ROSSI', all).map((e) => e.id), ['1', '4']);
    });
    test('per numero di ombrellone', () {
      expect(searchBookings('T1-1', all).map((e) => e.id), ['4']);
      expect(searchBookings('2', all).map((e) => e.id), ['3']);
    });
    test('per telefono (almeno 4 cifre)', () {
      expect(searchBookings('1112', all).map((e) => e.id), ['1']);
      expect(searchBookings('333', all), isEmpty);
    });
    test('ricerca vuota', () => expect(searchBookings('  ', all), isEmpty));
  });

  test('knownClients unisce lo stesso nome e tiene il telefono', () {
    final clients = knownClients(all);
    expect(clients.keys.where((k) => k.toLowerCase() == 'rossi mario').length, 1);
    expect(clients.entries.firstWhere((e) => e.key.toLowerCase() == 'rossi mario').value, '333 111 2222');
    expect(clients.containsKey('Senza Nome'), isFalse);
  });

  test('occupancyOn conta gli ombrelloni occupati per settore', () {
    final sectors = [
      BeachSector(name: 'Mare', crossAxisCount: 3, rows: 1, umbrellas: [
        Umbrella(id: 'Mare-1', sectorName: 'Mare', index: 0),
        Umbrella(id: 'Mare-2', sectorName: 'Mare', index: 1),
        Umbrella(id: 'Mare-3', sectorName: 'Mare', index: 2),
      ]),
      BeachSector(name: 'Tende', crossAxisCount: 1, rows: 1, umbrellas: [Umbrella(id: 'Tende-T1-1', sectorName: 'Tende', index: 0)]),
    ];
    final occ = occupancyOn(d(7, 4), sectors, all);
    expect(occ[0].occupied, 2);
    expect(occ[0].total, 3);
    expect(occ[0].ratio, closeTo(0.667, 0.01));
    expect(occ[1].occupied, 0);
    expect(const SectorOccupancy('Vuoto', 0, 0).ratio, 0);
  });

  test('moneySummary e lista da incassare', () {
    final m = moneySummary(all);
    expect(m.collected, 140); // 100 di acconto + 40 saldati
    expect(m.due, 200);
    expect(m.bookingsWithDue, 1);
    expect(bookingsWithAmountDue(all).map((e) => e.id), ['3']);
  });

  group('whatsappNumber', () {
    test('cellulare italiano senza prefisso', () => expect(whatsappNumber('333 123 4567'), '393331234567'));
    test('con +39 e simboli', () => expect(whatsappNumber('+39 (333) 123-4567'), '393331234567'));
    test('con 0039', () => expect(whatsappNumber('0039 3331234567'), '393331234567'));
    test('fisso italiano', () => expect(whatsappNumber('0541 123456'), '390541123456'));
    test('estero', () => expect(whatsappNumber('+49 151 23456789'), '4915123456789'));
    test('non valido', () {
      expect(whatsappNumber(''), isNull);
      expect(whatsappNumber('abc'), isNull);
      expect(whatsappNumber('123'), isNull);
    });
  });

  group('parseAmountInput', () {
    test('virgola e simbolo euro', () {
      expect(parseAmountInput('12,50'), 12.5);
      expect(parseAmountInput('€ 30'), 30);
    });
    test('vuoto o non valido', () {
      expect(parseAmountInput(''), isNull);
      expect(parseAmountInput('dieci'), isNull);
      expect(parseAmountInput('-5'), isNull);
    });
  });

  test('formatEuro', () {
    expect(formatEuro(120), '€ 120');
    expect(formatEuro(12.5), '€ 12,50');
    expect(formatEuro(0.1 + 0.2), '€ 0,30');
  });

  group('bookingSummaryMessage', () {
    test('con acconto', () {
      final msg = bookingSummaryMessage(all[2]);
      expect(msg, contains('Verdi'));
      expect(msg, contains('ombrellone 2 (Mare)'));
      expect(msg, contains('dal 03/07/2027 al 20/07/2027'));
      expect(msg, contains('acconto versato € 100'));
      expect(msg, contains('da saldare € 200'));
    });
    test('senza prezzo', () {
      expect(bookingSummaryMessage(all[1]), isNot(contains('Totale')));
    });
    test('saldato', () {
      expect(bookingSummaryMessage(all[3]), contains('(saldato)'));
    });
  });

  test('nextUmbrellaNumber: il più alto + 1, come nella versione originale', () {
    expect(nextUmbrellaNumber({}), 1);
    expect(nextUmbrellaNumber({1, 2, 3}), 4);
    expect(nextUmbrellaNumber({1, 2, 4, 5}), 6);
  });
}
