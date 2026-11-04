import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicazione_gestionale/availability.dart';
import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/models.dart';
import 'package:applicazione_gestionale/suggester.dart';

/// Simulazione di una stagione intera: centinaia di operazioni casuali (ma
/// ripetibili) come farebbe la famiglia in un'estate. Dopo ogni passo si
/// controllano le regole che devono valere SEMPRE.

BeachSector sector(String name, int count, {bool tende = false}) => BeachSector(
      name: name,
      crossAxisCount: 10,
      rows: (count / 10).ceil(),
      umbrellas: [
        for (var i = 0; i < count; i++)
          Umbrella(id: tende ? 'Tende-T${i ~/ 5 + 1}-${i % 5 + 1}' : '$name-${i + 1}', sectorName: name, index: i),
      ],
    );

final sectors = [sector('Mare', 30), sector('Tende', 10, tende: true), sector('Dietro', 20)];
final allUmbrellas = {for (final s in sectors) for (final u in s.umbrellas) u.id: u};

const names = ['Rossi', 'Bianchi', 'Verdi', 'Neri', 'Gialli', 'Ferri', 'Galli', 'Conti', 'Costa', 'Greco', 'Bruno', 'Marino'];

void main() {
  late FakeFirebaseFirestore db;
  late BookingService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    final repo = BookingRepository(firestore: db, clock: () => DateTime(2027, 6, 1));
    service = BookingService(repository: repo, currentUserName: () => 'Simulazione');
  });

  Future<List<Booking>> load() async => (await db.collection('bookings').get()).docs.map(Booking.fromFirestore).toList();

  /// Le regole che devono valere sempre.
  void checkInvariants(List<Booking> all, String step) {
    for (final b in all) {
      expect(b.clientName.trim(), isNotEmpty, reason: '$step: nome vuoto');
      expect(dayOnly(b.endDate).isBefore(dayOnly(b.startDate)), isFalse, reason: '$step: date al contrario in ${b.id}');
      final u = allUmbrellas[b.umbrellaId];
      expect(u, isNotNull, reason: '$step: ombrellone inesistente ${b.umbrellaId}');
      expect(b.sectorName, u!.sectorName, reason: '$step: settore sbagliato per ${b.umbrellaId}');
      expect(b.amountDue >= 0 && b.amountCollected >= 0, isTrue, reason: '$step: importi negativi');
    }
    // Mai due prenotazioni sovrapposte sullo stesso ombrellone.
    final byUmbrella = <String, List<Booking>>{};
    for (final b in all) {
      byUmbrella.putIfAbsent(b.umbrellaId, () => []).add(b);
    }
    for (final list in byUmbrella.values) {
      list.sort((a, b) => a.startDate.compareTo(b.startDate));
      for (var i = 1; i < list.length; i++) {
        expect(dayOnly(list[i].startDate).isAfter(dayOnly(list[i - 1].endDate)), isTrue,
            reason: '$step: sovrapposizione su ${list[i].umbrellaId} tra ${list[i - 1].id} e ${list[i].id}');
      }
    }
  }

  test('una stagione di 600 operazioni casuali non rompe mai le regole', () async {
    final rnd = Random(2027);
    final seasonStart = DateTime(2027, 6, 1);
    DateTime randomDay() => DateTime(seasonStart.year, seasonStart.month, seasonStart.day + rnd.nextInt(105));
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;

    for (var step = 0; step < 600; step++) {
      final all = await load();
      final op = rnd.nextInt(100);
      final label = 'passo $step';

      if (op < 55 || all.isEmpty) {
        // Nuova prenotazione: il settore si sceglie sempre per primo.
        final s = sectors[rnd.nextInt(sectors.length)];
        final start = randomDay();
        final range = DateTimeRange(start: start, end: DateTime(start.year, start.month, start.day + rnd.nextInt(14)));
        Umbrella target;
        if (rnd.nextBool()) {
          final suggestions = suggestUmbrellas(range: range, sectors: [s], bookings: all, sectorName: s.name);
          // I suggerimenti sono sempre liberi e del settore scelto.
          for (final sug in suggestions) {
            expect(sug.umbrella.sectorName, s.name, reason: '$label: suggerimento fuori settore');
            expect(bookingsInRange(sug.umbrella.id, range, all), isEmpty, reason: '$label: suggerito un ombrellone occupato');
          }
          if (suggestions.isEmpty) {
            count('settore pieno');
            continue;
          }
          target = suggestions.first.umbrella;
        } else {
          target = s.umbrellas[rnd.nextInt(s.umbrellas.length)];
        }
        final price = rnd.nextBool() ? (rnd.nextInt(30) + 1) * 10.0 : null;
        final candidate = Booking(
          umbrellaId: target.id,
          clientName: names[rnd.nextInt(names.length)],
          startDate: range.start,
          endDate: range.end,
          price: price,
          deposit: price != null && rnd.nextBool() ? price / 2 : 0,
        );
        try {
          await service.save(candidate);
          count('creata');
        } on BookingConflictException catch (e) {
          // Il rifiuto deve essere giusto: c'era davvero una sovrapposizione.
          expect(e.conflict.umbrellaId, target.id);
          expect(e.conflict.overlaps(range), isTrue, reason: '$label: conflitto inventato');
          count('rifiutata (occupato)');
        }
      } else if (op < 70) {
        // Spostamento, di solito nello stesso settore.
        final b = all[rnd.nextInt(all.length)];
        final sameSector = rnd.nextInt(100) < 85;
        final pool = sameSector ? sectors.firstWhere((s) => s.name == b.sectorName).umbrellas : allUmbrellas.values.toList();
        final target = pool[rnd.nextInt(pool.length)];
        try {
          await service.move(b, target.id, b.range);
          count('spostata');
        } on BookingConflictException {
          count('spostamento rifiutato');
        }
      } else if (op < 80) {
        // Allungare di qualche giorno.
        final b = all[rnd.nextInt(all.length)];
        final longer = b.copyWith(endDate: DateTime(b.endDate.year, b.endDate.month, b.endDate.day + 1 + rnd.nextInt(5)));
        try {
          await service.save(longer);
          count('allungata');
        } on BookingConflictException catch (e) {
          expect(e.conflict.id, isNot(b.id), reason: '$label: in conflitto con se stessa');
          count('allungamento rifiutato');
        }
      } else if (op < 90) {
        // Eliminazione, a volte annullata subito.
        final b = all[rnd.nextInt(all.length)];
        await service.delete(b);
        count('eliminata');
        if (rnd.nextBool()) {
          await service.restore(b); // nessuno ha preso il posto nel frattempo
          count('ripristinata');
        }
      } else {
        // Arrivi e pagamenti.
        final b = all[rnd.nextInt(all.length)];
        if (rnd.nextBool()) {
          await service.setArrived(b, !b.arrived);
          count('arrivo');
        } else {
          await service.setPaid(b, true);
          count('pagamento');
        }
      }

      if (step % 10 == 0 || step == 599) checkInvariants(await load(), label);
    }

    final finalBookings = await load();
    checkInvariants(finalBookings, 'fine stagione');
    // La simulazione deve aver fatto davvero un po' di tutto.
    expect(stats['creata'] ?? 0, greaterThan(150));
    expect(stats['rifiutata (occupato)'] ?? 0, greaterThan(0));
    expect(stats['spostata'] ?? 0, greaterThan(10));
    expect(stats['ripristinata'] ?? 0, greaterThan(5));
    expect(finalBookings.length, greaterThan(100));

    // Riepiloghi coerenti con i dati.
    final money = moneySummary(finalBookings);
    final collected = finalBookings.fold<double>(0, (s, b) => s + b.amountCollected);
    expect(money.collected, closeTo(collected, 0.001));
    for (var day = 0; day < 105; day += 7) {
      final date = DateTime(2027, 6, 1 + day);
      for (final o in occupancyOn(date, sectors, finalBookings)) {
        expect(o.occupied, lessThanOrEqualTo(o.total));
      }
    }
    // ignore: avoid_print
    print('Simulazione stagione: $stats · prenotazioni finali ${finalBookings.length}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
