import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/main.dart';
import 'package:applicazione_gestionale/map_screen.dart';
import 'package:applicazione_gestionale/sector_style.dart';

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
  BeachSector(name: 'Mare', crossAxisCount: 3, rows: 1, umbrellas: [
    Umbrella(id: 'Mare-1', sectorName: 'Mare', index: 0),
    Umbrella(id: 'Mare-2', sectorName: 'Mare', index: 1),
    Umbrella(id: 'Mare-3', sectorName: 'Mare', index: 2),
  ]),
  BeachSector(name: 'Tende', crossAxisCount: 2, rows: 1, umbrellas: [
    Umbrella(id: 'Tende-T1-1', sectorName: 'Tende', index: 0),
    Umbrella(id: 'Tende-T1-2', sectorName: 'Tende', index: 1),
  ]),
  BeachSector(name: 'Dietro', crossAxisCount: 1, rows: 1, umbrellas: [Umbrella(id: 'Dietro-1', sectorName: 'Dietro', index: 0)]),
];

DateTime d(int day) => DateTime(2027, 7, day);
final range = DateTimeRange(start: d(10), end: d(12));

void main() {
  late BookingRepository repo;

  setUpAll(() => initializeDateFormatting('it'));

  setUp(() {
    repo = BookingRepository(firestore: FakeFirebaseFirestore(), clock: () => d(1));
    BookingRepository.instance = repo;
    BookingService.instance = BookingService(repository: repo, currentUserName: () => 'Test');
  });

  Future<void> useBigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  final bookings = [
    Booking(id: 'a', umbrellaId: 'Mare-1', clientName: 'Rossi', startDate: d(11), endDate: d(11)),
    Booking(id: 'b', umbrellaId: 'Tende-T1-1', clientName: 'Bianchi', startDate: d(1), endDate: d(31)),
    Booking(id: 'c', umbrellaId: 'Tende-T1-2', clientName: 'Verdi', startDate: d(12), endDate: d(14)),
  ];

  test('freeUmbrellas: liberi per TUTTO il periodo, settore per settore', () {
    expect(freeUmbrellas(sectors[0], range, bookings), 2);
    expect(freeUmbrellas(sectors[1], range, bookings), 0);
    expect(freeUmbrellas(sectors[2], range, bookings), 1);
  });

  test('ogni settore ha icona e colore propri', () {
    final styles = ['Mare', 'Tende', 'Dietro'].map(SectorStyle.of).toList();
    expect(styles.map((s) => s.icon).toSet(), hasLength(3));
    expect(styles.map((s) => s.color).toSet(), hasLength(3));
    expect(SectorStyle.of('Altro').icon, Icons.grid_view);
  });

  testWidgets('scelta del settore con i posti liberi', (tester) async {
    await useBigScreen(tester);
    String? chosen;
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => chosen = await chooseSector(context, sectors: sectors, range: range, bookings: bookings),
            child: const Text('apri'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('In quale settore?'), findsOneWidget);
    expect(find.text('2 liberi su 3'), findsOneWidget);
    expect(find.text('Pieno per queste date'), findsOneWidget);
    expect(find.text('1 liberi su 1'), findsOneWidget);
    await tester.tap(find.text('Dietro'));
    await tester.pumpAndSettle();
    expect(chosen, 'Dietro');
  });

  testWidgets('mappa: si apre sul settore scelto e la barra cambia settore', (tester) async {
    await useBigScreen(tester);
    final semantics = tester.ensureSemantics();
    repo.bookings.value = bookings;
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: range, initialSector: 'Tende')));
    await tester.pump();

    // solo il settore Tende sulla mappa
    expect(find.text('T1-1'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Ombrellone 1, ')), findsNothing, reason: 'Mare e Dietro nascosti');
    expect(find.bySemanticsLabel('Tende, 0 liberi'), findsOneWidget);
    expect(find.bySemanticsLabel('Mare, 2 liberi'), findsOneWidget);
    expect(find.bySemanticsLabel('Tutti, 3 liberi'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Mare, 2 liberi'));
    await tester.pump();
    expect(find.text('T1-1'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Ombrellone 2, libero')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Tutti, 3 liberi'));
    await tester.pump();
    expect(find.text('T1-1'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Ombrellone 2, libero')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('la scheda mostra l\'etichetta colorata del settore', (tester) async {
    await useBigScreen(tester);
    repo.bookings.value = [];
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: range, initialSector: 'Dietro')));
    await tester.pump();
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SectorBadge, 'Settore: Dietro'), findsOneWidget);
  });

  testWidgets('ricerca: risultati divisi per settore', (tester) async {
    await useBigScreen(tester);
    final all = [
      ...bookings,
      Booking(id: 'd', umbrellaId: 'Dietro-1', clientName: 'Rossi Anna', startDate: d(20), endDate: d(22)),
    ];
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showSearch<Booking?>(context: context, delegate: BookingSearchDelegate(all)),
            child: const Text('cerca'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('cerca'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rossi');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SectorBadge, 'Mare · 1'), findsOneWidget);
    expect(find.widgetWithText(SectorBadge, 'Dietro · 1'), findsOneWidget);
    final mareY = tester.getCenter(find.text('Mare · 1')).dy;
    final dietroY = tester.getCenter(find.text('Dietro · 1')).dy;
    expect(mareY, lessThan(dietroY), reason: 'ordine: Mare, Tende, Dietro');
  });
}
