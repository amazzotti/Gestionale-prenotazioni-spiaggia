import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:applicazione_gestionale/arrivi_oggi_screen.dart';
import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/map_screen.dart';
import 'package:applicazione_gestionale/stats_screen.dart';

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
];

Booking booking(String id, String umbrella, DateTime start, DateTime end, {String name = 'Cliente', double? price, double deposit = 0}) =>
    Booking(id: id, umbrellaId: umbrella, clientName: name, startDate: start, endDate: end, price: price, deposit: deposit);

void main() {
  late FakeFirebaseFirestore db;
  late BookingRepository repo;

  setUpAll(() => initializeDateFormatting('it'));

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = BookingRepository(firestore: db, clock: () => DateTime(2027, 7, 1));
    BookingRepository.instance = repo;
    BookingService.instance = BookingService(repository: repo, currentUserName: () => 'test@test.it');
  });

  Future<void> useBigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  group('Mappa', () {
    final range = DateTimeRange(start: DateTime(2027, 7, 1), end: DateTime(2027, 7, 10));

    testWidgets('mostra legenda, anteprima del periodo e stato degli ombrelloni', (tester) async {
      await useBigScreen(tester);
      final semantics = tester.ensureSemantics();
      repo.bookings.value = [
        booking('a', 'Mare-1', DateTime(2027, 7, 1), DateTime(2027, 7, 10), name: 'Tutto', price: 100),
        booking('b', 'Mare-2', DateTime(2027, 7, 3), DateTime(2027, 7, 4), name: 'Parte'),
      ];
      await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: range)));
      await tester.pump();

      expect(find.text('Libero'), findsOneWidget);
      expect(find.text('In parte'), findsNothing, reason: 'niente più arancione');
      expect(find.text('Occupato'), findsOneWidget);
      // anteprima del periodo su due righe
      for (final t in ['01/07', '10/07', '03/07', '04/07']) {
        expect(find.text(t), findsOneWidget);
      }
      // L'etichetta di accessibilità inizia con numero e stato (poi segue il testo del quadrato).
      expect(find.bySemanticsLabel(RegExp(r'^Ombrellone 1, occupato(\n|$)')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Ombrellone 2, occupato(\n|$)')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Ombrellone 3, libero(\n|$)')), findsOneWidget);
      // € sul quadrato di chi deve ancora pagare (più quello della legenda)
      expect(find.byIcon(Icons.euro), findsNWidgets(2));
      semantics.dispose();
    });

    testWidgets('pressione lunga: chi c\'era prima, chi c\'è nel periodo e chi arriva dopo', (tester) async {
      await useBigScreen(tester);
      repo.bookings.value = [
        booking('p', 'Mare-2', DateTime(2027, 6, 20), DateTime(2027, 6, 28), name: 'Verdi Prima'),
        booking('b', 'Mare-2', DateTime(2027, 7, 3), DateTime(2027, 7, 4), name: 'Nel Mezzo'),
        booking('n', 'Mare-2', DateTime(2027, 7, 11), DateTime(2027, 7, 15), name: 'Neri Dopo'),
      ];
      await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: range)));
      await tester.pump();

      await tester.longPress(find.text('2'));
      await tester.pumpAndSettle();
      expect(find.text('Ombrellone 2 · Mare'), findsOneWidget);
      expect(find.text('PRIMA'), findsOneWidget);
      expect(find.text('Verdi Prima'), findsOneWidget);
      expect(find.text('poi 2 giorni liberi prima del periodo'), findsOneWidget);
      expect(find.text('NEL PERIODO 01/07 - 10/07'), findsOneWidget);
      expect(find.text('Nel Mezzo'), findsOneWidget);
      expect(find.text('DOPO'), findsOneWidget);
      expect(find.text('Neri Dopo'), findsOneWidget);
      expect(find.text('arriva il giorno dopo il periodo'), findsOneWidget);
    });

    testWidgets('la scheda prenotazione mostra chi c\'è prima e dopo', (tester) async {
      await useBigScreen(tester);
      repo.bookings.value = [
        booking('p', 'Mare-3', DateTime(2027, 6, 25), DateTime(2027, 6, 30), name: 'Gialli'),
        booking('n', 'Mare-3', DateTime(2027, 7, 14), DateTime(2027, 7, 20), name: 'Blu'),
      ];
      await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: range)));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(find.text('Prima: Gialli, fino al 30/06 (subito)'), findsOneWidget);
      expect(find.text('Dopo: Blu, dal 14/07 (3 giorni liberi)'), findsOneWidget);
    });

    testWidgets('nuova prenotazione dal form fino al salvataggio su Firestore', (tester) async {
      await useBigScreen(tester);
      repo.bookings.value = [];
      await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: range)));
      await tester.pump();

      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(find.text('Ombrellone 3'), findsOneWidget);
      expect(find.text('10 giorni'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Nome Cliente'), 'Verdi Anna');
      await tester.enterText(find.widgetWithText(TextField, 'Telefono (facoltativo)'), '333 1234567');
      await tester.enterText(find.widgetWithText(TextField, 'Prezzo €'), '150');
      await tester.enterText(find.widgetWithText(TextField, 'Acconto €'), '50');
      await tester.pump();
      expect(find.text('Da incassare: € 100'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('SALVA'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      final docs = await tester.runAsync(() => db.collection('bookings').get());
      expect(docs!.docs, hasLength(1));
      final data = docs.docs.single.data();
      expect(data['clientName'], 'Verdi Anna');
      expect(data['umbrellaId'], 'Mare-3');
      expect(data['phone'], '333 1234567');
      expect(data['price'], 150);
      expect(data['deposit'], 50);
      expect(data['updatedBy'], 'test@test.it');
      expect(find.text('Prenotazione salvata.'), findsOneWidget);
    });

    testWidgets('il form segnala nome mancante e importi non validi', (tester) async {
      await useBigScreen(tester);
      repo.bookings.value = [];
      await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: range)));
      await tester.pump();
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Prezzo €'), 'tanti');
      await tester.tap(find.text('SALVA'));
      await tester.pump();
      expect(find.text('Prezzo non valido.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Prezzo €'), '');
      await tester.runAsync(() async {
        await tester.tap(find.text('SALVA'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Inserisci il nome del cliente.'), findsOneWidget);
    });

    testWidgets('selettore del giorno: frecce e OGGI', (tester) async {
      await useBigScreen(tester);
      repo.bookings.value = [];
      final day = DateTimeRange(start: DateTime(2027, 7, 14), end: DateTime(2027, 7, 14));
      await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: day)));
      await tester.pump();
      expect(find.text('mer 14/07/2027'), findsOneWidget);
      await tester.tap(find.byTooltip('Giorno dopo'));
      await tester.pump();
      expect(find.text('gio 15/07/2027'), findsOneWidget);
      await tester.tap(find.byTooltip('Giorno prima'));
      await tester.tap(find.byTooltip('Giorno prima'));
      await tester.pump();
      expect(find.text('mar 13/07/2027'), findsOneWidget);
    });
  });

  testWidgets('Arrivi e partenze del giorno con importo da incassare', (tester) async {
    await useBigScreen(tester);
    repo.bookings.value = [
      booking('a', 'Mare-1', DateTime(2027, 7, 14), DateTime(2027, 7, 20), name: 'Arriva', price: 100, deposit: 20),
      booking('b', 'Mare-2', DateTime(2027, 7, 1), DateTime(2027, 7, 14), name: 'Parte'),
    ];
    await tester.pumpWidget(app(ArriviOggiScreen(initialDate: DateTime(2027, 7, 14))));
    await tester.pump();

    expect(find.text('Arriva'), findsOneWidget);
    expect(find.text('Ombrellone 1 · Mare'), findsOneWidget);
    expect(find.text('Da incassare € 80'), findsOneWidget);
    expect(find.text('Parte'), findsNothing);

    await tester.tap(find.text('PARTENZE'));
    await tester.pumpAndSettle();
    expect(find.text('Parte'), findsOneWidget);
  });

  testWidgets('Statistiche: occupazione e incassi', (tester) async {
    await useBigScreen(tester);
    final today = DateTime(2027, 7, 1); // "oggi" secondo l'orologio del repository di test
    repo.bookings.value = [
      booking('a', 'Mare-1', today, today, name: 'Uno', price: 100, deposit: 40),
      Booking(id: 'b', umbrellaId: 'Mare-2', clientName: 'Due', startDate: today, endDate: today, price: 60, paid: true),
    ];
    await tester.pumpWidget(app(StatsScreen(beachSectors: sectors)));
    await tester.pump();

    expect(find.text('Totale: 2 su 3'), findsOneWidget);
    expect(find.text('Mare: 2 su 3 (67%)'), findsOneWidget);
    expect(find.text('€ 100'), findsNWidgets(2)); // incassato 40 + 60: totale e riga "Mare"
    expect(find.text('€ 60'), findsNWidgets(3)); // da incassare: totale, riga "Mare", elenco
    expect(find.text('Per settore'), findsOneWidget);
    expect(find.text('MARE'), findsOneWidget, reason: 'elenco da incassare diviso per settore');
    expect(find.text('Uno - Ombr. 1'), findsOneWidget);
  });
}
