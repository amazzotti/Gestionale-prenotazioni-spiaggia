// Genera le anteprime dell'app (PNG a misura di telefono) nella cartella screenshots/ del repo.
//
//   cd applicazione_gestionale
//   flutter test screenshots_test --update-goldens
//
// Non fa parte dei test normali (flutter test non lo esegue) perché i PNG cambiano da PC a PC.
// Le anteprime non stanno in test/ (così la CI non le confronta), quindi l'analizzatore non le considera test.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:applicazione_gestionale/arrivi_oggi_screen.dart';
import 'package:applicazione_gestionale/auth_gate.dart';
import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/booking_service.dart';
import 'package:applicazione_gestionale/device_service.dart';
import 'package:applicazione_gestionale/devices_screen.dart';
import 'package:applicazione_gestionale/help_screen.dart';
import 'package:applicazione_gestionale/layout_repository.dart';
import 'package:applicazione_gestionale/main.dart';
import 'package:applicazione_gestionale/map_screen.dart';
import 'package:applicazione_gestionale/planner_screen.dart';
import 'package:applicazione_gestionale/sector_style.dart';
import 'package:applicazione_gestionale/stats_screen.dart';

final today = DateTime(2027, 7, 14);
DateTime day(int d) => DateTime(2027, 7, d);

Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File('$dir/$f').readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    }
    await loader.load();
  }

  await load('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

/// Settori come sono costruiti con l'editor (stesso formato di Firestore).
Map<String, dynamic> sectorData(String name, int rows, int cols, {List<int> walkways = const [], bool tende = false}) {
  final umbrellas = <Map<String, dynamic>>[];
  var n = 0;
  final perRow = <int, int>{};
  for (var i = 0; i < rows * cols; i++) {
    if (walkways.contains(i % cols)) continue;
    final row = i ~/ cols;
    if (tende) {
      perRow[row] = (perRow[row] ?? 0) + 1;
      umbrellas.add({'id': 'T${row + 1}-${perRow[row]}', 'index': i});
    } else {
      umbrellas.add({'id': '${++n}', 'index': i});
    }
  }
  return {'name': name, 'rows': rows, 'crossAxisCount': cols, 'umbrellas': umbrellas, 'walkwayColumns': walkways};
}

final layout = [
  sectorData('Mare', 4, 9, walkways: [4]),
  sectorData('Tende', 2, 8, tende: true),
  sectorData('Dietro', 3, 9, walkways: [4]),
];

const names = [
  'Rossi Mario', 'Bianchi Laura', 'Ferrari Luca', 'Esposito Anna', 'Romano Giulia', 'Colombo Marco', 'Ricci Sara',
  'Marino Paolo', 'Greco Elena', 'Bruno Davide', 'Gallo Chiara', 'Conti Andrea', 'De Luca Marta', 'Mancini Pietro',
  'Costa Silvia', 'Giordano Fabio', 'Rizzo Valentina', 'Lombardi Simone', 'Moretti Ilaria', 'Barbieri Stefano',
  'Fontana Roberta', 'Santoro Matteo', 'Mariani Francesca', 'Rinaldi Giorgio', 'Caruso Alessia', 'Ferrara Nicola',
];

List<Booking> sampleBookings() {
  final list = <Booking>[];
  var k = 0;
  Booking add(String umbrella, int from, int to, {double? price, double deposit = 0, bool paid = false, bool arrived = false, String notes = '', String phone = ''}) {
    final b = Booking(
      id: 'b${k++}',
      umbrellaId: umbrella,
      clientName: names[k % names.length],
      startDate: day(from),
      endDate: day(to),
      price: price,
      deposit: deposit,
      paid: paid,
      arrived: arrived,
      notes: notes,
      phone: phone.isEmpty ? '333 ${1000000 + k * 7919}' : phone,
    );
    list.add(b);
    return b;
  }

  // Mare: quasi pieno
  for (var u = 1; u <= 32; u++) {
    if (u % 7 == 0) continue; // qualche posto libero
    if (u % 5 == 0) {
      add('Mare-$u', 10, 13, price: 80, deposit: 20); // finisce prima: parziale nel periodo
      continue;
    }
    add('Mare-$u', 6 + u % 8, 18 + u % 6, price: 150 + u * 5.0, deposit: u % 3 == 0 ? 50 : 0, paid: u % 4 == 0, arrived: u % 2 == 0);
  }
  // Tende
  for (var t = 1; t <= 8; t++) {
    if (t == 3) continue;
    add('Tende-T1-$t', 1, 31, price: 900, paid: t.isEven, arrived: true);
    if (t < 6) add('Tende-T2-$t', 12, 16, price: 220, deposit: 60);
  }
  // Dietro: metà
  for (var u = 1; u <= 24; u += 2) {
    add('Dietro-$u', 13 + u % 3, 15 + u % 4, price: 60);
  }
  // arrivi di oggi con note
  add('Dietro-2', 14, 20, price: 120, deposit: 40, notes: 'Lettino extra per il bambino', phone: '347 555 1234');
  add('Dietro-4', 14, 16, notes: 'Arrivano nel pomeriggio');
  return list;
}

Widget app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green), useMaterial3: true),
      home: home,
    );

void main() {
  late FakeFirebaseFirestore db;
  late BookingRepository repo;
  late List<BeachSector> sectors;

  setUpAll(() async {
    await initializeDateFormatting('it');
    await loadFonts();
    PackageInfo.setMockInitialValues(appName: 'Gestionale', packageName: 'x', version: '1.0.0', buildNumber: '1', buildSignature: '');
  });

  setUp(() async {
    db = FakeFirebaseFirestore();
    for (final s in layout) {
      await db.collection('beachLayout').doc(s['name'] as String).set(s);
    }
    repo = BookingRepository(firestore: db, clock: () => today.add(const Duration(hours: 10)));
    BookingRepository.instance = repo;
    LayoutRepository.instance = LayoutRepository(firestore: db);
    BookingService.instance = BookingService(repository: repo, currentUserName: () => 'Telefono di mamma');
    DeviceService.instance = DeviceService(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'aleX42pq', isAnonymous: true)),
    );
    await db.collection('dispositivi').doc('aleX42pq').set({'nome': 'Telefono di Ale', 'ruolo': 'admin'});
    await db.collection('dispositivi').doc('mAm7Hk2b').set({'nome': 'Telefono di mamma', 'ruolo': 'admin'});
    await db.collection('dispositivi').doc('pApa91Zt').set({'nome': 'Tablet della cassa', 'ruolo': 'staff'});
    await db.collection('richieste').doc('k7Qm2xPa9Lz').set({'nome': 'Telefono di Giulia', 'richiestoIl': Timestamp.now()});
    final bookings = sampleBookings();
    for (final b in bookings) {
      await db.collection('bookings').doc(b.id).set({...b.toFirestore(), 'updatedBy': 'Telefono di mamma', 'updatedAt': Timestamp.now()});
    }
    repo.bookings.value = (await db.collection('bookings').get()).docs.map(Booking.fromFirestore).toList();
    sectors = BeachSector.sorted(layout.map(BeachSector.fromMap));
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../screenshots/$name.png'));
  }

  testWidgets('01 home', (tester) async {
    await phone(tester);
    await tester.pumpWidget(MyApp(home: const HomeScreen(isAdmin: true)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await shot(tester, '01_home');
  });

  testWidgets('02 mappa di oggi', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors)));
    await shot(tester, '02_mappa_oggi');
  });

  testWidgets('03 mappa periodo con anteprima e ombrelloni arancioni', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: DateTimeRange(start: day(12), end: day(18)))));
    await shot(tester, '03_mappa_periodo');
  });

  testWidgets('04 scheda prenotazione', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').first);
    await shot(tester, '04_scheda_prenotazione');
  });

  testWidgets('05 elenco prenotazioni di un ombrellone', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors, filterDateRange: DateTimeRange(start: day(12), end: day(18)))));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('5').first);
    await shot(tester, '05_elenco_ombrellone');
  });

  testWidgets('06 annulla dopo eliminazione', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(MapScreen(beachSectors: sectors)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ELIMINA'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('ELIMINA'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    // nei test non c'è il listener di Firestore: tolgo a mano la prenotazione eliminata
    repo.bookings.value = repo.bookings.value!.where((b) => !(b.umbrellaId == 'Mare-1' && b.coversDay(today))).toList();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../screenshots/06_annulla_eliminazione.png'));
  });

  testWidgets('07 arrivi e partenze', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(const ArriviOggiScreen()));
    await shot(tester, '07_arrivi');
  });

  testWidgets('08 incassi e statistiche', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(StatsScreen(beachSectors: sectors)));
    await shot(tester, '08_statistiche');
  });

  testWidgets('09 telefono in attesa di approvazione', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(const WaitingApprovalScreen(uid: 'gIu5Rx8Tq2W')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.enterText(find.byType(TextField), 'Telefono di Giulia');
    await shot(tester, '09_attesa_approvazione');
  });

  testWidgets('10 telefoni', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(const DevicesScreen()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await shot(tester, '10_telefoni');
  });

  testWidgets('11 planner', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(PlannerScreen(beachSectors: sectors)));
    await shot(tester, '11_planner');
  });

  testWidgets('12 planner sposta', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(PlannerScreen(beachSectors: sectors)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bianchi Laura').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('SPOSTA SU ALTRO OMBRELLONE'));
    await shot(tester, '12_planner_sposta');
  });

  testWidgets('13 suggeritore', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(MapScreen(
        beachSectors: sectors, filterDateRange: DateTimeRange(start: day(15), end: day(19)), initialSector: 'Mare', openSuggestions: true)));
    await shot(tester, '13_suggeritore');
  });

  testWidgets('14 guida', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(const HelpScreen(initialTopic: HelpTopic.mappa)));
    await shot(tester, '14_guida');
  });

  testWidgets('15 scelta del settore', (tester) async {
    await phone(tester);
    await tester.pumpWidget(app(Builder(builder: (context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        chooseSector(context, sectors: sectors, range: DateTimeRange(start: day(15), end: day(19)), bookings: repo.bookings.value!);
      });
      return const Scaffold(body: SizedBox.expand());
    })));
    await shot(tester, '15_scelta_settore');
  });
}
