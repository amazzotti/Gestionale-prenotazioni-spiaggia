import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicazione_gestionale/availability.dart';
import 'package:applicazione_gestionale/beach_editor_screen.dart';
import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/layout_repository.dart';
import 'package:applicazione_gestionale/models.dart';

/// Test delle correzioni nate dalla revisione del codice prima della V1.0.0.

DateTime d(int month, int day) => DateTime(2027, month, day);

void main() {
  group('Ora legale', () {
    test('daysBetween e Booking.days non perdono un giorno a fine marzo', () {
      // In Italia il 28/03/2027 dura 23 ore.
      expect(daysBetween(DateTime(2027, 3, 27), DateTime(2027, 3, 29)), 2);
      final b = Booking(umbrellaId: 'Mare-1', clientName: 'x', startDate: DateTime(2027, 3, 27), endDate: DateTime(2027, 3, 29));
      expect(b.days, 3);
    });

    test('addDays a fine ottobre dà davvero il giorno dopo', () {
      expect(addDays(DateTime(2026, 10, 25), 1), DateTime(2026, 10, 26));
      expect(addDays(DateTime(2027, 3, 28), 1), DateTime(2027, 3, 29));
    });
  });

  group('Editor: ridimensionare la griglia', () {
    test('ogni ombrellone resta nella sua riga e colonna', () {
      // griglia 2x3: posizioni 0..5; ombrelloni in (0,0), (0,2), (1,1)
      final r = resizeLayout({0: 'Mare-1', 2: 'Mare-2', 4: 'Mare-3'}, oldCols: 3, newRows: 2, newCols: 5);
      expect(r.kept, {0: 'Mare-1', 2: 'Mare-2', 6: 'Mare-3'}); // (1,1) con 5 colonne = 6
      expect(r.dropped, isEmpty);
    });

    test('quelli che escono dalla griglia vengono segnalati', () {
      final r = resizeLayout({0: 'Mare-1', 2: 'Mare-2', 4: 'Mare-3'}, oldCols: 3, newRows: 1, newCols: 2);
      expect(r.kept, {0: 'Mare-1'});
      expect(r.dropped, ['Mare-2', 'Mare-3']);
    });
  });

  group('Salvataggi sicuri', () {
    late FakeFirebaseFirestore db;
    late BookingService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = BookingService(repository: BookingRepository(firestore: db, clock: () => d(7, 1)), currentUserName: () => 'Test');
    });

    Future<Booking> create() async {
      final id = await service.save(Booking(umbrellaId: 'Mare-1', clientName: 'Rossi', startDate: d(7, 1), endDate: d(7, 5)));
      return Booking.fromFirestore(await db.collection('bookings').doc(id).get());
    }

    test('una scheda aperta da tempo non annulla "arrivato" messo da un altro telefono', () async {
      final opened = await create(); // la scheda si apre qui
      await service.setArrived(opened, true); // intanto un altro telefono segna l'arrivo
      final edited = opened.copyWith(notes: 'vicino alla doccia');
      await service.save(edited, original: opened);
      final data = (await db.collection('bookings').doc(opened.id).get()).data()!;
      expect(data['notes'], 'vicino alla doccia');
      expect(data['arrived'], isTrue, reason: 'non riportato a false');
    });

    test('scrive solo i campi cambiati', () {
      final a = Booking(id: 'x', umbrellaId: 'Mare-1', clientName: 'Rossi', startDate: d(7, 1), endDate: d(7, 5), price: 100);
      expect(BookingService.changedFields(a, a), isEmpty);
      final fields = BookingService.changedFields(a, a.copyWith(price: 120, umbrellaId: 'Mare-2'));
      expect(fields.keys.toSet(), {'price', 'umbrellaId'});
    });

    test('una prenotazione eliminata da un altro telefono non viene ricreata', () async {
      final opened = await create();
      await service.delete(opened);
      expect(
        () => service.save(opened.copyWith(notes: 'modifica tardiva'), original: opened),
        throwsA(isA<BookingValidationException>().having((e) => e.message, 'messaggio', contains('eliminata da un altro telefono'))),
      );
      expect(() => service.move(opened, 'Mare-2', opened.range), throwsA(isA<BookingValidationException>()));
      expect((await db.collection('bookings').doc(opened.id).get()).exists, isFalse);
    });

    test('spostare cambia solo ombrellone e date', () async {
      final opened = await create();
      await service.setPaid(opened, true); // pagato nel frattempo
      await service.move(opened, 'Mare-3', DateTimeRange(start: d(7, 2), end: d(7, 6)));
      final data = (await db.collection('bookings').doc(opened.id).get()).data()!;
      expect(data['umbrellaId'], 'Mare-3');
      expect(data['paid'], isTrue);
    });

    test('senza connessione non salva (meglio che rischiare una doppia prenotazione)', () async {
      service.debugOffline = true;
      expect(
        () => service.save(Booking(umbrellaId: 'Mare-1', clientName: 'Rossi', startDate: d(7, 1), endDate: d(7, 5))),
        throwsA(isA<BookingOfflineException>()),
      );
      expect((await db.collection('bookings').get()).docs, isEmpty);
    });
  });

  group('Repository', () {
    late FakeFirebaseFirestore db;
    late BookingRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = BookingRepository(firestore: db, clock: () => d(9, 15));
    });

    test('la conversione dei dati vecchi ripulisce i valori fuori misura', () async {
      final ref = await db.collection('bookings').add({
        'id': 'Mare-4',
        'nome': '',
        'telefono': '333 1111111 / 347 2222222 (moglie)',
        'data_inizio': '10/07/2027',
        'data_fine': '12/07/2027',
      });
      expect(await repo.migrateToSchema2(), 1);
      final data = (await ref.get()).data()!;
      expect(data['clientName'], 'Senza nome');
      expect((data['phone'] as String).length, lessThanOrEqualTo(30));
    });

    test('reset di stagione: di default restano le prenotazioni future', () async {
      Future<void> add(String id, DateTime start, DateTime end) =>
          db.collection('bookings').doc(id).set(Booking(umbrellaId: 'Mare-1', clientName: id, startDate: start, endDate: end).toFirestore());
      await add('finita', d(7, 1), d(7, 10));
      await add('in-corso', d(9, 10), d(9, 20));
      await add('futura', DateTime(2028, 6, 1), DateTime(2028, 6, 10));

      expect(await repo.deleteSeason(), 1);
      final left = (await db.collection('bookings').get()).docs.map((e) => e.id).toSet();
      expect(left, {'in-corso', 'futura'});

      expect(await repo.deleteSeason(includeFuture: true), 2);
      expect((await db.collection('bookings').get()).docs, isEmpty);
    });

    test('due avvii di fila lasciano un solo collegamento', () async {
      await db.collection('bookings').add(Booking(umbrellaId: 'Mare-1', clientName: 'A', startDate: d(7, 1), endDate: d(7, 2)).toFirestore());
      final first = repo.start(isAdmin: false);
      final second = repo.start(isAdmin: false);
      await Future.wait([first, second]);
      for (var i = 0; i < 50 && repo.bookings.value == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(repo.bookings.value, hasLength(1));
      await repo.stop();
      expect(repo.isStarted, isFalse);
    });
  });

  group('Editor mappa (schermata)', () {
    late FakeFirebaseFirestore db;

    setUp(() async {
      db = FakeFirebaseFirestore();
      LayoutRepository.instance = LayoutRepository(firestore: db);
      final repo = BookingRepository(firestore: db, clock: () => d(7, 1));
      BookingRepository.instance = repo;
      // Mare 2 righe x 3 colonne: ombrelloni 1 (0,0), 2 (0,2), 3 (1,1)
      await db.collection('beachLayout').doc('Mare').set({
        'name': 'Mare',
        'rows': 2,
        'crossAxisCount': 3,
        'umbrellas': [
          {'id': '1', 'index': 0},
          {'id': '2', 'index': 2},
          {'id': '3', 'index': 4},
        ],
        'walkwayColumns': [],
      });
      repo.bookings.value = [Booking(id: 'p', umbrellaId: 'Mare-3', clientName: 'Prenotato', startDate: d(7, 5), endDate: d(7, 8))];
    });

    Widget app() => const MaterialApp(
          locale: Locale('it', 'IT'),
          supportedLocales: [Locale('it', 'IT')],
          localizationsDelegates: [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: BeachEditorScreen(),
        );

    Future<void> openMare(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mare').last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    testWidgets('scrivere nei campi non cambia la griglia finché non premi ✓', (tester) async {
      await openMare(tester);
      Finder inGrid(String n) => find.descendant(of: find.byType(GridView), matching: find.text(n));
      expect(inGrid('3'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Colonne'), '1'); // a metà della digitazione
      await tester.pump();
      for (final n in ['1', '2', '3']) {
        expect(inGrid(n), findsOneWidget, reason: 'nessun ombrellone sparito mentre si scrive');
      }

      await tester.enterText(find.widgetWithText(TextField, 'Colonne'), '5');
      await tester.tap(find.byTooltip('Applica righe e colonne'));
      await tester.pumpAndSettle();
      for (final n in ['1', '2', '3']) {
        expect(inGrid(n), findsOneWidget, reason: 'ombrellone $n ancora presente');
      }
      // stessa riga e colonna: il 3 era in (1,1), con 5 colonne è il 7° quadrato (indice 6)
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect((grid.childrenDelegate as SliverChildBuilderDelegate).estimatedChildCount, 10);
    });

    testWidgets('non si possono togliere ombrelloni con prenotazioni rimpicciolendo la griglia', (tester) async {
      await openMare(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Righe'), '1');
      await tester.tap(find.byTooltip('Applica righe e colonne'));
      await tester.pumpAndSettle();
      expect(find.textContaining('gli ombrelloni 3 hanno prenotazioni'), findsOneWidget);
      expect(find.widgetWithText(TextField, '2'), findsOneWidget, reason: 'le righe tornano a 2');
    });
  });
}
