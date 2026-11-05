import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/models.dart';
import 'package:applicazione_gestionale/planner_screen.dart';
import 'package:applicazione_gestionale/system_bars.dart';

/// Sui Samsung (Android 15+) l'ultima riga del planner finiva sotto i tasti
/// indietro / home. Ora la schermata si ferma sul bordo della barra.
void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets('planner: scorrendo in fondo, l\'ultima riga resta sopra la barra dei tasti', (tester) async {
    final repo = BookingRepository(firestore: FakeFirebaseFirestore(), clock: () => DateTime(2027, 7, 9));
    BookingRepository.instance = repo;
    BookingService.instance = BookingService(repository: repo, currentUserName: () => 'Test');
    repo.bookings.value = [];

    tester.view.physicalSize = const Size(1080, 2200); // 540 x 1100
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(bottom: 96); // barra dei tasti alta 48
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    addTearDown(tester.view.reset);

    final sectors = [
      BeachSector(name: 'Mare', crossAxisCount: 10, rows: 4, umbrellas: [
        for (var i = 0; i < 40; i++) Umbrella(id: 'Mare-${i + 1}', sectorName: 'Mare', index: i),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => SystemBarsSafeArea(child: child!),
      home: PlannerScreen(beachSectors: sectors),
    ));
    await tester.pump();

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.text('Ombr.'), const Offset(0, -800), warnIfMissed: false);
      await tester.dragFrom(const Offset(270, 800), const Offset(0, -800));
      await tester.pumpAndSettle();
    }

    const barTop = 1100.0 - 48;
    final last = find.text('40');
    expect(last, findsOneWidget);
    expect(tester.getBottomLeft(last).dy, lessThanOrEqualTo(barTop));
    // la riga sotto l'ultima etichetta (fine della griglia) non va oltre la barra
    final scaffoldBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
    expect(scaffoldBottom, lessThanOrEqualTo(barTop));
  });
}
