import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicazione_gestionale/models.dart';
import 'package:applicazione_gestionale/suggester.dart';

DateTime d(int month, int day) => DateTime(2027, month, day);
DateTimeRange r(DateTime a, DateTime b) => DateTimeRange(start: a, end: b);

Booking b(String umbrella, DateTime start, DateTime end, {String name = 'Cliente'}) =>
    Booking(id: '$umbrella-$start', umbrellaId: umbrella, clientName: name, startDate: start, endDate: end);

Umbrella u(String sector, int n, int index) => Umbrella(id: '$sector-$n', sectorName: sector, index: index);

final sectors = [
  BeachSector(name: 'Dietro', crossAxisCount: 2, rows: 1, umbrellas: [u('Dietro', 1, 0), u('Dietro', 2, 1)]),
  BeachSector(name: 'Mare', crossAxisCount: 4, rows: 1, umbrellas: [u('Mare', 1, 0), u('Mare', 2, 1), u('Mare', 3, 2), u('Mare', 4, 3)]),
];

void main() {
  final range = r(d(7, 10), d(7, 14));

  final bookings = [
    // Mare-1: occupato nel periodo -> escluso
    b('Mare-1', d(7, 12), d(7, 13), name: 'Occupa'),
    // Mare-2: incastro perfetto (finisce il 9, il successivo arriva il 15)
    b('Mare-2', d(7, 1), d(7, 9), name: 'Prima'),
    b('Mare-2', d(7, 15), d(7, 20), name: 'Dopo'),
    // Mare-3: attaccato a una prenotazione precedente, poi tutto libero
    b('Mare-3', d(7, 3), d(7, 9), name: 'Giorgi'),
    // Mare-4: completamente libero
    // Dietro-1: buco largo (2 giorni prima, 3 dopo)
    b('Dietro-1', d(7, 1), d(7, 7), name: 'A'),
    b('Dietro-1', d(7, 18), d(7, 20), name: 'B'),
  ];

  test('esclude gli ombrelloni occupati anche solo un giorno', () {
    final s = suggestUmbrellas(range: range, sectors: sectors, bookings: bookings, limit: 10);
    expect(s.map((e) => e.umbrella.id), isNot(contains('Mare-1')));
  });

  test('incastro perfetto, poi attaccato da un lato, poi buco stretto, per ultimi i liberi', () {
    final s = suggestUmbrellas(range: range, sectors: sectors, bookings: bookings, limit: 10);
    expect(s.map((e) => e.umbrella.id), ['Mare-2', 'Mare-3', 'Dietro-1', 'Mare-4', 'Dietro-2']);
    expect(s[0].reasons.single, 'Incastro perfetto: riempie esattamente il buco tra Prima e Dopo');
    expect(s[1].reasons.single, 'Subito dopo Giorgi');
    expect(s[2].reasons.single, 'Lascia 2 giorni liberi prima e 3 giorni liberi dopo');
    expect(s[3].reasons.single, 'Libero per tutta la stagione');
  });

  test('a parità di punteggio segue l\'ordine della mappa (Mare prima di Dietro)', () {
    final s = suggestUmbrellas(range: range, sectors: sectors, bookings: bookings, limit: 10);
    expect(s.indexWhere((e) => e.umbrella.id == 'Mare-4'), lessThan(s.indexWhere((e) => e.umbrella.id == 'Dietro-2')));
  });

  test('filtro per settore', () {
    final s = suggestUmbrellas(range: range, sectors: sectors, bookings: bookings, sectorName: 'Dietro');
    expect(s.map((e) => e.umbrella.sectorName).toSet(), {'Dietro'});
  });

  test('l\'ombrellone abituale del cliente va in cima', () {
    final s = suggestUmbrellas(range: range, sectors: sectors, bookings: bookings, clientName: ' giorgi ');
    expect(s.first.umbrella.id, 'Mare-3');
    expect(s.first.isHabitual, isTrue);
    expect(s.first.reasons.first, 'giorgi ha già avuto questo ombrellone');
  });

  test('limit e nessun posto libero', () {
    expect(suggestUmbrellas(range: range, sectors: sectors, bookings: bookings, limit: 2), hasLength(2));
    final full = [for (final s in sectors) for (final x in s.umbrellas) b(x.id, d(7, 1), d(7, 31))];
    expect(suggestUmbrellas(range: range, sectors: sectors, bookings: full), isEmpty);
  });
}
