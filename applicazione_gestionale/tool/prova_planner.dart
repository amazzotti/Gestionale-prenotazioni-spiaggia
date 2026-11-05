// Prova su emulatore o telefono, senza Firebase: apre il planner con dati finti.
// flutter run -t tool/prova_planner.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/main.dart';
import 'package:applicazione_gestionale/models.dart';
import 'package:applicazione_gestionale/planner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it');
  final repo = BookingRepository(firestore: FakeFirebaseFirestore());
  BookingRepository.instance = repo;
  BookingService.instance = BookingService(repository: repo, currentUserName: () => 'Prova');
  final today = repo.today;
  repo.bookings.value = [
    Booking(id: 'a', umbrellaId: 'Mare-60', clientName: 'Ultima Riga', startDate: today, endDate: today.add(const Duration(days: 3))),
    Booking(id: 'b', umbrellaId: 'Mare-1', clientName: 'Prima Riga', startDate: today, endDate: today.add(const Duration(days: 2))),
  ];
  final sectors = [
    BeachSector(name: 'Mare', crossAxisCount: 10, rows: 6, umbrellas: [
      for (var i = 0; i < 60; i++) Umbrella(id: 'Mare-${i + 1}', sectorName: 'Mare', index: i),
    ]),
  ];
  runApp(MyApp(home: PlannerScreen(beachSectors: sectors)));
}
