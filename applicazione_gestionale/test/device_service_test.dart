import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:applicazione_gestionale/auth_gate.dart';
import 'package:applicazione_gestionale/booking_repository.dart';
import 'package:applicazione_gestionale/device_service.dart';

void main() {
  group('DeviceService', () {
    late FakeFirebaseFirestore db;
    late DeviceService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = DeviceService(firestore: db, auth: MockFirebaseAuth());
    });

    test('entra in Firebase da solo e mantiene lo stesso codice', () async {
      final uid = await service.ensureSignedIn();
      expect(uid, isNotEmpty);
      expect(await service.ensureSignedIn(), uid);
      expect(service.currentUid, uid);
    });

    test('shortCode è corto e leggibile', () {
      expect(DeviceService.shortCode('aB3-dE9xyz'), 'AB3DE9');
      expect(DeviceService.shortCode('ab'), 'AB');
    });

    test('cleanName toglie spazi, limita la lunghezza e ha un nome di ripiego', () {
      expect(DeviceService.cleanName('  Telefono   di  mamma '), 'Telefono di mamma');
      expect(DeviceService.cleanName(''), 'Telefono');
      expect(DeviceService.cleanName('x' * 60).length, DeviceService.maxNameLength);
    });

    test('richiesta, approvazione e stato del telefono', () async {
      final uid = await service.ensureSignedIn();
      final states = <ApprovedDevice?>[];
      final sub = service.watchMyDevice(uid).listen(states.add);

      expect(await service.hasPendingRequest(uid), isFalse);
      await service.requestAccess(uid, 'Telefono di mamma');
      expect(await service.hasPendingRequest(uid), isTrue);

      final requests = await service.watchRequests().first;
      expect(requests.single.name, 'Telefono di mamma');
      expect(requests.single.code, DeviceService.shortCode(uid));

      service.currentDeviceName = 'Telefono di Ale';
      await service.approve(requests.single, role: DeviceRole.staff, name: 'Mamma');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await service.watchRequests().first, isEmpty, reason: 'la richiesta approvata sparisce');
      final device = states.whereType<ApprovedDevice>().last;
      expect(device.name, 'Mamma');
      expect(device.isAdmin, isFalse);
      expect(service.currentDeviceName, 'Mamma');
      final data = (await db.collection('dispositivi').doc(uid).get()).data()!;
      expect(data['approvatoDa'], 'Telefono di Ale');
      await sub.cancel();
    });

    test('rifiutare una richiesta la cancella', () async {
      await service.requestAccess('altro', 'Sconosciuto');
      final r = (await service.watchRequests().first).single;
      await service.reject(r);
      expect(await service.watchRequests().first, isEmpty);
    });

    test('si può togliere l\'accesso agli altri ma non a se stessi', () async {
      final uid = await service.ensureSignedIn();
      await db.collection('dispositivi').doc(uid).set({'nome': 'Io', 'ruolo': 'admin'});
      await db.collection('dispositivi').doc('altro').set({'nome': 'Altro', 'ruolo': 'staff'});
      final devices = await service.watchDevices().first;
      expect(devices.map((d) => d.name), ['Altro', 'Io']);

      expect(() => service.revoke(devices.firstWhere((d) => d.uid == uid)), throwsStateError);
      await service.revoke(devices.firstWhere((d) => d.uid == 'altro'));
      expect((await service.watchDevices().first).map((d) => d.name), ['Io']);
    });

    test('ruoli sconosciuti valgono come "solo prenotazioni"', () {
      expect(ApprovedDevice.fromMap('x', {'nome': 'A', 'ruolo': 'superuser'}).isAdmin, isFalse);
      expect(ApprovedDevice.fromMap('x', {'ruolo': 'admin'}).name, 'Telefono');
    });
  });

  group('AuthGate (nessuna schermata di login)', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;

    setUp(() {
      PackageInfo.setMockInitialValues(appName: 'a', packageName: 'b', version: '1.0.0', buildNumber: '1', buildSignature: '');
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'telefono123', isAnonymous: true));
      DeviceService.instance = DeviceService(firestore: db, auth: auth);
      BookingRepository.instance = BookingRepository(firestore: db, clock: () => DateTime(2027, 7, 1));
    });

    Widget gate() => MaterialApp(
          home: AuthGate(builder: (context, {required isAdmin}) => Text(isAdmin ? 'HOME ADMIN' : 'HOME STAFF')),
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    testWidgets('telefono nuovo: chiede un nome e invia la richiesta', (tester) async {
      await tester.pumpWidget(gate());
      await settle(tester);
      expect(find.text('Questo telefono non è ancora abilitato'), findsOneWidget);
      expect(find.text('TELEFO'), findsOneWidget, reason: 'codice breve del telefono');

      await tester.enterText(find.byType(TextField), 'Telefono di mamma');
      await tester.runAsync(() async {
        await tester.tap(find.text('CHIEDI L\'ACCESSO'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Richiesta inviata!'), findsOneWidget);
      final req = await tester.runAsync(() => db.collection('richieste').doc('telefono123').get());
      expect(req!.data()!['nome'], 'Telefono di mamma');
    });

    testWidgets('telefono approvato: si apre direttamente l\'app', (tester) async {
      await db.collection('dispositivi').doc('telefono123').set({'nome': 'Mamma', 'ruolo': 'staff'});
      await tester.pumpWidget(gate());
      await settle(tester);
      expect(find.text('HOME STAFF'), findsOneWidget);
    });

    testWidgets('si sblocca da solo quando viene approvato e si richiude se l\'accesso è tolto', (tester) async {
      await tester.pumpWidget(gate());
      await settle(tester);
      expect(find.text('Questo telefono non è ancora abilitato'), findsOneWidget);

      await tester.runAsync(() => db.collection('dispositivi').doc('telefono123').set({'nome': 'Ale', 'ruolo': 'admin'}));
      await settle(tester);
      expect(find.text('HOME ADMIN'), findsOneWidget);

      await tester.runAsync(() => db.collection('dispositivi').doc('telefono123').delete());
      await settle(tester);
      expect(find.text('HOME ADMIN'), findsNothing);
      expect(find.text('Questo telefono non è ancora abilitato'), findsOneWidget);
    });
  });
}
