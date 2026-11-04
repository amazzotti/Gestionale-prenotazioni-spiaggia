import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/help_screen.dart';
import 'package:applicazione_gestionale/map_screen.dart';
import 'package:applicazione_gestionale/suggestions_sheet.dart';

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
  BeachSector(name: 'Dietro', crossAxisCount: 1, rows: 1, umbrellas: [Umbrella(id: 'Dietro-1', sectorName: 'Dietro', index: 0)]),
];

DateTime d(int day) => DateTime(2027, 7, day);

/// Testo dentro il pannello dei suggerimenti (la mappa dietro ha anche la scritta MARE).
Finder inPanel(String text) => find.descendant(of: find.byType(SuggestionsPanel), matching: find.text(text));

void main() {
  late BookingRepository repo;

  setUpAll(() => initializeDateFormatting('it'));

  setUp(() {
    PackageInfo.setMockInitialValues(appName: 'a', packageName: 'b', version: '1.0.0', buildNumber: '1', buildSignature: '');
    repo = BookingRepository(firestore: FakeFirebaseFirestore(), clock: () => d(1));
    BookingRepository.instance = repo;
    BookingService.instance = BookingService(repository: repo, currentUserName: () => 'Test');
  });

  Future<void> useBigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('suggeritore: si apre da solo, consiglia l\'incastro migliore e compila la scheda', (tester) async {
    await useBigScreen(tester);
    repo.bookings.value = [
      Booking(id: 'a', umbrellaId: 'Mare-1', clientName: 'Occupa', startDate: d(10), endDate: d(12)),
      Booking(id: 'b', umbrellaId: 'Mare-2', clientName: 'Prima', startDate: d(1), endDate: d(9)),
      Booking(id: 'c', umbrellaId: 'Mare-2', clientName: 'Dopo', startDate: d(13), endDate: d(20)),
      Booking(id: 'e', umbrellaId: 'Dietro-1', clientName: 'Ferri Anna', startDate: d(1), endDate: d(3), phone: '333 1112222'),
    ];
    final range = DateTimeRange(start: d(10), end: d(12));
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: range, openSuggestions: true)));
    await tester.pumpAndSettle();

    expect(find.text('Dove la metto?'), findsOneWidget);
    expect(find.text('Ombrellone 2 · Mare'), findsOneWidget);
    expect(find.text('Incastro perfetto: riempie esattamente il buco tra Prima e Dopo'), findsOneWidget);
    expect(find.text('Ombrellone 1 · Mare'), findsNothing, reason: 'occupato nel periodo');

    // il cliente abituale passa in cima
    await tester.enterText(find.widgetWithText(TextField, 'Cliente (facoltativo)'), 'Ferri Anna');
    await tester.pump();
    expect(find.text('Ferri Anna ha già avuto questo ombrellone'), findsOneWidget);

    // i settori restano separati: l'ombrellone abituale è in cima alla sezione DIETRO
    expect(inPanel('MARE'), findsOneWidget);
    expect(inPanel('DIETRO'), findsOneWidget);
    final dietroCard = find.ancestor(of: find.text('Ombrellone 1 · Dietro'), matching: find.byType(Card));
    final button = find.descendant(of: dietroCard, matching: find.text('PRENOTA QUI'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Ombrellone 1'), findsOneWidget);
    expect(find.text('Settore: Dietro'), findsOneWidget, reason: 'l\'ombrellone abituale di Ferri Anna è il Dietro 1');
    expect(find.widgetWithText(TextField, 'Ferri Anna'), findsOneWidget, reason: 'nome già scritto');
    expect(find.widgetWithText(TextField, '333 1112222'), findsOneWidget, reason: 'telefono del cliente già visto');
  });

  testWidgets('suggeritore dalla lampadina con filtro settore', (tester) async {
    await useBigScreen(tester);
    repo.bookings.value = [Booking(id: 'x', umbrellaId: 'Dietro-1', clientName: 'Pieno', startDate: d(1), endDate: d(31))];
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: DateTimeRange(start: d(10), end: d(12)))));
    await tester.pump();
    await tester.tap(find.byTooltip('Dove la metto? (suggerimenti)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dietro'));
    await tester.pump();
    expect(find.text('Nessun posto libero in Dietro per tutto il periodo.'), findsOneWidget);
    expect(find.text('Ombrellone 1 · Mare'), findsNothing, reason: 'non propone mai un altro settore da solo');
    expect(inPanel('MARE'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Tutti i settori'));
    await tester.pump();
    expect(inPanel('MARE'), findsOneWidget);
    expect(find.text('Ombrellone 1 · Mare'), findsOneWidget);
  });

  testWidgets('guida: si apre sull\'argomento richiesto', (tester) async {
    await useBigScreen(tester);
    await tester.pumpWidget(app(const HelpScreen(initialTopic: HelpTopic.planner)));
    await tester.pumpAndSettle();
    expect(find.text('Guida'), findsOneWidget);
    expect(find.text('Il planner (calendario)'), findsOneWidget);
    expect(find.textContaining('Le righe verdi sono quelle libere'), findsOneWidget, reason: 'argomento aperto');
    expect(find.text('La mappa'), findsOneWidget);
    expect(find.textContaining('Verde = libero'), findsNothing, reason: 'gli altri argomenti sono chiusi');

    await tester.tap(find.text('La mappa'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verde = libero'), findsOneWidget);
  });

  testWidgets('la legenda della mappa porta alla guida', (tester) async {
    await useBigScreen(tester);
    repo.bookings.value = [];
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors)));
    await tester.pump();
    await tester.tap(find.text('Guida'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verde = libero'), findsOneWidget);
  });
}
