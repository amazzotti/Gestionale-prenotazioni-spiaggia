import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicazione_gestionale/availability.dart';
import 'package:applicazione_gestionale/models.dart';
import 'package:applicazione_gestionale/suggester.dart';

DateTime d(int day) => DateTime(2027, 7, day);

Booking b(String umbrella, {double? price, double deposit = 0, bool paid = false, String name = 'Cliente'}) =>
    Booking(id: umbrella, umbrellaId: umbrella, clientName: name, startDate: d(10), endDate: d(12), price: price, deposit: deposit, paid: paid);

final sectors = [
  BeachSector(name: 'Dietro', crossAxisCount: 1, rows: 1, umbrellas: [Umbrella(id: 'Dietro-1', sectorName: 'Dietro', index: 0)]),
  BeachSector(name: 'Tende', crossAxisCount: 1, rows: 1, umbrellas: [Umbrella(id: 'Tende-T1-1', sectorName: 'Tende', index: 0)]),
  BeachSector(name: 'Mare', crossAxisCount: 2, rows: 1, umbrellas: [
    Umbrella(id: 'Mare-1', sectorName: 'Mare', index: 0),
    Umbrella(id: 'Mare-2', sectorName: 'Mare', index: 1),
  ]),
];

void main() {
  group('Tutto diviso per settore', () {
    test('groupBySector: ordine Mare, Tende, Dietro anche senza mappa', () {
      final list = [b('Dietro-1'), b('Mare-2'), b('Tende-T1-1'), b('Mare-1')];
      final groups = groupBySector(list, const []);
      expect(groups.map((g) => g.$1), ['Mare', 'Tende', 'Dietro']);
      expect(groups.first.$2.map((e) => e.umbrellaId), ['Mare-2', 'Mare-1'], reason: 'mantiene l\'ordine interno');
      expect(groupBySector(list, sectors).map((g) => g.$1), ['Mare', 'Tende', 'Dietro']);
      expect(groupBySector(const [], sectors), isEmpty);
    });

    test('moneyBySector: incassi separati per settore', () {
      final list = [
        b('Mare-1', price: 100, deposit: 30),
        b('Mare-2', price: 50, paid: true),
        b('Tende-T1-1', price: 900, deposit: 200),
      ];
      final m = {for (final s in moneyBySector(sectors, list)) s.sector: s.money};
      expect(m.keys, ['Mare', 'Tende', 'Dietro']);
      expect(m['Mare']!.collected, 80);
      expect(m['Mare']!.due, 70);
      expect(m['Tende']!.collected, 200);
      expect(m['Tende']!.due, 700);
      expect(m['Dietro']!.collected, 0);
    });

    test('suggestBySector: una classifica per settore, mai mescolati', () {
      final range = DateTimeRange(start: d(10), end: d(12));
      final groups = suggestBySector(range: range, sectors: sectors, bookings: [b('Mare-1')]);
      expect(groups.map((g) => g.$1.name), ['Mare', 'Tende', 'Dietro']);
      for (final (sector, list) in groups) {
        expect(list.every((s) => s.umbrella.sectorName == sector.name), isTrue);
      }
      expect(groups.first.$2.map((s) => s.umbrella.id), ['Mare-2']);
    });

    test('suggestBySector: l\'ombrellone abituale vale solo nel suo settore', () {
      final range = DateTimeRange(start: d(20), end: d(22));
      final past = [b('Tende-T1-1', name: 'Rossi')];
      final groups = suggestBySector(range: range, sectors: sectors, bookings: past, clientName: 'Rossi');
      final tende = groups.firstWhere((g) => g.$1.name == 'Tende').$2;
      final mare = groups.firstWhere((g) => g.$1.name == 'Mare').$2;
      expect(tende.first.isHabitual, isTrue);
      expect(mare.any((s) => s.isHabitual), isFalse);
    });
  });
}
