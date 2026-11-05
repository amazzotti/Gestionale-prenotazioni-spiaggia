// Prova su emulatore o telefono, senza Firebase: apre il planner con dati finti.
// flutter run -t tool/prova_planner.dart   (anche con --release)
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:ui' show ViewPadding;

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
  // Nessun accesso a Firebase: il planner legge solo le prenotazioni passate qui sotto.
  final repo = BookingRepository();
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
  runApp(_MisureSchermo(child: MyApp(home: PlannerScreen(beachSectors: sectors))));
}

/// Mostra sopra l'app le misure che Android comunica a Flutter (barre di sistema),
/// per capire come si comporta un telefono specifico.
class _MisureSchermo extends StatefulWidget {
  final Widget child;
  const _MisureSchermo({required this.child});

  @override
  State<_MisureSchermo> createState() => _MisureSchermoState();
}

class _MisureSchermoState extends State<_MisureSchermo> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final v = WidgetsBinding.instance.platformDispatcher.views.first;
    final r = v.devicePixelRatio;
    String fmt(ViewPadding p) => 'sopra ${(p.top / r).toStringAsFixed(0)} · sotto ${(p.bottom / r).toStringAsFixed(0)}';
    final text = 'schermo ${(v.physicalSize.width / r).toStringAsFixed(0)}x${(v.physicalSize.height / r).toStringAsFixed(0)} · dpr ${r.toStringAsFixed(2)}\n'
        'padding: ${fmt(v.padding)}\n'
        'viewPadding: ${fmt(v.viewPadding)}\n'
        'gesture: ${fmt(v.systemGestureInsets)}';
    debugPrint('MISURE $text');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        widget.child,
        Positioned(
          left: 8,
          right: 8,
          top: 300,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xCC000000),
              child: Text(text, style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14, decoration: TextDecoration.none)),
            ),
          ),
        ),
      ]),
    );
  }
}
