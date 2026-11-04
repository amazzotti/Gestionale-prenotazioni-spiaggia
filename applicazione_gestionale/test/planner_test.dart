import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/models.dart';
import 'package:applicazione_gestionale/planner_screen.dart';

Widget app(Widget home) => MaterialApp(
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

final sectors = [
  BeachSector(name: 'Tende', crossAxisCount: 3, rows: 1, umbrellas: [
    Umbrella(id: 'Tende-T1-1', sectorName: 'Tende', index: 0),
    Umbrella(id: 'Tende-T1-2', sectorName: 'Tende', index: 1),
    Umbrella(id: 'Tende-T1-3', sectorName: 'Tende', index: 2),
  ]),
];

DateTime d(int month, int day) => DateTime(2027, month, day);

void main() {
  late FakeFirebaseFirestore db;
  late BookingRepository repo;

  setUpAll(() => initializeDateFormatting('it'));

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = BookingRepository(firestore: db, clock: () => d(7, 9));
    BookingRepository.instance = repo;
    BookingService.instance = BookingService(repository: repo, currentUserName: () => 'Test');
  });

  Future<void> useBigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> setBookings(WidgetTester tester, List<Booking> list) async {
    await tester.runAsync(() async {
      for (final b in list) {
        await db.collection('bookings').doc(b.id).set(b.toFirestore());
      }
    });
    repo.bookings.value = list;
  }

  /// Punto su una riga del planner, al giorno [dayIndex] della finestra.
  Offset rowPoint(WidgetTester tester, String label, int dayIndex) {
    final y = tester.getCenter(find.text(label)).dy;
    final x = tester.getTopRight(find.text('Ombr.')).dx;
    final left = tester.getTopLeft(find.byType(Scaffold)).dx + 58;
    return Offset((x > left ? x : left) + dayIndex * 46 + 20, y);
  }

  final highlight = DateTimeRange(start: d(7, 10), end: d(7, 12));

  testWidgets('mostra le prenotazioni come barre: rosse nel periodo, grigie prima e dopo', (tester) async {
    await useBigScreen(tester);
    final semantics = tester.ensureSemantics();
    await setBookings(tester, [
      Booking(id: 'a', umbrellaId: 'Tende-T1-1', clientName: 'Rossi Lungo', startDate: d(7, 1), endDate: d(7, 11)),
      Booking(id: 'b', umbrellaId: 'Tende-T1-2', clientName: 'Bianchi Dopo', startDate: d(7, 14), endDate: d(7, 16)),
      Booking(id: 'c', umbrellaId: 'Tende-T1-3', clientName: 'Fuori Finestra', startDate: d(9, 1), endDate: d(9, 5)),
    ]);
    await tester.pumpWidget(app(PlannerScreen(beachSectors: sectors, highlightRange: highlight)));
    await tester.pump();

    expect(find.text('Planner'), findsOneWidget);
    expect(find.text('Dal 07/07 al 03/08'), findsOneWidget, reason: 'finestra: 3 giorni prima del periodo, 4 settimane');
    expect(find.text('Nel periodo 10/07-12/07'), findsOneWidget);
    expect(find.text('Rossi Lungo'), findsOneWidget);
    expect(find.text('Bianchi Dopo'), findsOneWidget);
    expect(find.text('Fuori Finestra'), findsNothing, reason: 'fuori dalle 4 settimane mostrate');

    Color barColor(String name) {
      final container = tester.widget<Container>(find.ancestor(of: find.text(name), matching: find.byType(Container)).first);
      return (container.decoration as BoxDecoration).color!;
    }

    expect(barColor('Rossi Lungo'), Colors.red.shade400);
    expect(barColor('Bianchi Dopo'), Colors.blueGrey.shade300);
    // la barra iniziata prima della finestra ha la freccia a sinistra
    expect(find.byIcon(Icons.chevron_left), findsWidgets);
    semantics.dispose();
  });

  testWidgets('tocco su uno spazio vuoto: nuova prenotazione fino al giorno prima della successiva', (tester) async {
    await useBigScreen(tester);
    await setBookings(tester, [
      Booking(id: 'n', umbrellaId: 'Tende-T1-3', clientName: 'Arriva Dopo', startDate: d(7, 11), endDate: d(7, 15)),
    ]);
    await tester.pumpWidget(app(PlannerScreen(beachSectors: sectors, highlightRange: highlight)));
    await tester.pump();

    await tester.tapAt(rowPoint(tester, 'T1-3', 1)); // 08/07
    await tester.pumpAndSettle();
    expect(find.text('Ombrellone T1-3'), findsOneWidget);
    expect(find.text('08/07/2027'), findsOneWidget);
    expect(find.text('10/07/2027'), findsOneWidget);
    expect(find.text('Dopo: Arriva Dopo, dal 11/07 (subito)'), findsOneWidget);
  });

  testWidgets('sposta: tocco sulla barra, "sposta", tocco sulla riga libera', (tester) async {
    await useBigScreen(tester);
    await setBookings(tester, [
      Booking(id: 'mv', umbrellaId: 'Tende-T1-1', clientName: 'Da Spostare', startDate: d(7, 10), endDate: d(7, 12)),
      Booking(id: 'oc', umbrellaId: 'Tende-T1-2', clientName: 'Occupato', startDate: d(7, 11), endDate: d(7, 13)),
    ]);
    await tester.pumpWidget(app(PlannerScreen(beachSectors: sectors, highlightRange: highlight)));
    await tester.pump();

    await tester.tap(find.text('Da Spostare'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('SPOSTA SU ALTRO OMBRELLONE'));
    await tester.pumpAndSettle();
    expect(find.text('SPOSTA: Da Spostare · dal 10/07 al 12/07'), findsOneWidget);

    // riga occupata: rifiutata
    await tester.runAsync(() async {
      await tester.tapAt(rowPoint(tester, 'T1-2', 0));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.textContaining('Occupato dal 11/07 al 13/07'), findsOneWidget);

    // riga libera: spostata
    await tester.runAsync(() async {
      await tester.tapAt(rowPoint(tester, 'T1-3', 0));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final moved = await tester.runAsync(() => db.collection('bookings').doc('mv').get());
    expect(moved!.data()!['umbrellaId'], 'Tende-T1-3');
    expect(find.text('Da Spostare spostato sull\'ombrellone T1-3.'), findsOneWidget);
    expect(find.text('Planner'), findsOneWidget, reason: 'esce dalla modalità sposta');
  });
}
