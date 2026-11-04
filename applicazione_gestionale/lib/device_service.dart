import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Ruoli dei telefoni approvati.
class DeviceRole {
  /// Tutto, compresi editor mappa, reset stagione e approvazione telefoni.
  static const admin = 'admin';

  /// Prenotazioni, arrivi e incassi.
  static const staff = 'staff';
}

/// Un telefono approvato (collezione `dispositivi`, ID = codice del telefono).
class ApprovedDevice {
  final String uid;
  final String name;
  final String role;
  const ApprovedDevice({required this.uid, required this.name, required this.role});

  bool get isAdmin => role == DeviceRole.admin;

  factory ApprovedDevice.fromMap(String uid, Map<String, dynamic> data) => ApprovedDevice(
        uid: uid,
        name: (data['nome'] as String?)?.trim().isNotEmpty == true ? data['nome'] as String : 'Telefono',
        role: data['ruolo'] == DeviceRole.admin ? DeviceRole.admin : DeviceRole.staff,
      );
}

/// Un telefono che ha chiesto di entrare (collezione `richieste`).
class AccessRequest {
  final String uid;
  final String name;
  final DateTime? requestedAt;
  const AccessRequest({required this.uid, required this.name, this.requestedAt});

  /// Codice breve da confrontare a voce con quello mostrato sul telefono.
  String get code => DeviceService.shortCode(uid);

  factory AccessRequest.fromMap(String uid, Map<String, dynamic> data) => AccessRequest(
        uid: uid,
        name: (data['nome'] as String?) ?? 'Telefono',
        requestedAt: (data['richiestoIl'] as Timestamp?)?.toDate(),
      );
}

/// Accesso senza login: approvazione dei telefoni.
///
/// - All'avvio l'app entra in Firebase in modo anonimo e invisibile: ogni
///   telefono riceve un codice univoco che resta lo stesso nel tempo.
/// - Un telefono vede i dati solo se il suo codice è nella collezione
///   `dispositivi` (lo controllano le regole Firestore sul server).
/// - Un telefono nuovo chiede l'accesso; un telefono admin lo approva.
class DeviceService {
  DeviceService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore,
        _auth = auth;

  static DeviceService? _instance;
  static DeviceService get instance => _instance ??= DeviceService();
  @visibleForTesting
  static set instance(DeviceService service) => _instance = service;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  FirebaseFirestore get db => _firestore ?? FirebaseFirestore.instance;
  FirebaseAuth get auth => _auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _devices => db.collection('dispositivi');
  CollectionReference<Map<String, dynamic>> get _requests => db.collection('richieste');

  static const int maxNameLength = 40;

  /// Nome di questo telefono, usato per "Ultima modifica".
  String? currentDeviceName;

  String? get currentUid => auth.currentUser?.uid;

  /// Codice breve e leggibile (6 caratteri) di un telefono.
  static String shortCode(String uid) {
    final clean = uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return clean.length <= 6 ? clean : clean.substring(0, 6);
  }

  /// Entra in Firebase senza chiedere niente. Restituisce il codice del telefono.
  Future<String> ensureSignedIn() async {
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    if (user == null) throw StateError('Accesso a Firebase non riuscito');
    return user.uid;
  }

  /// Segue lo stato di approvazione di questo telefono (null = non approvato).
  Stream<ApprovedDevice?> watchMyDevice(String uid) {
    return _devices.doc(uid).snapshots().map((s) {
      if (!s.exists) return null;
      final device = ApprovedDevice.fromMap(s.id, s.data()!);
      currentDeviceName = device.name;
      return device;
    });
  }

  static String cleanName(String name) {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return 'Telefono';
    return n.length > maxNameLength ? n.substring(0, maxNameLength) : n;
  }

  /// Chiede l'accesso per questo telefono, con un nome per riconoscerlo.
  Future<void> requestAccess(String uid, String name) {
    return _requests.doc(uid).set({'nome': cleanName(name), 'richiestoIl': FieldValue.serverTimestamp()});
  }

  /// true se questo telefono ha già inviato la richiesta.
  Future<bool> hasPendingRequest(String uid) async {
    try {
      return (await _requests.doc(uid).get()).exists;
    } catch (_) {
      return false;
    }
  }

  // ---------- Solo per i telefoni admin ----------

  Stream<List<AccessRequest>> watchRequests() => _requests.snapshots().map((s) =>
      s.docs.map((d) => AccessRequest.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => (b.requestedAt ?? DateTime(2000)).compareTo(a.requestedAt ?? DateTime(2000))));

  Stream<List<ApprovedDevice>> watchDevices() => _devices.snapshots().map((s) =>
      s.docs.map((d) => ApprovedDevice.fromMap(d.id, d.data())).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  /// Approva un telefono e cancella la sua richiesta.
  Future<void> approve(AccessRequest request, {required String role, String? name}) async {
    final batch = db.batch();
    batch.set(_devices.doc(request.uid), {
      'nome': cleanName(name ?? request.name),
      'ruolo': role == DeviceRole.admin ? DeviceRole.admin : DeviceRole.staff,
      'approvatoIl': FieldValue.serverTimestamp(),
      'approvatoDa': currentDeviceName ?? '',
    });
    batch.delete(_requests.doc(request.uid));
    await batch.commit();
  }

  Future<void> reject(AccessRequest request) => _requests.doc(request.uid).delete();

  /// Toglie l'accesso a un telefono. Non si può togliere a se stessi (per non restare chiusi fuori).
  Future<void> revoke(ApprovedDevice device) {
    if (device.uid == currentUid) {
      throw StateError('Non puoi togliere l\'accesso a questo telefono da se stesso.');
    }
    return _devices.doc(device.uid).delete();
  }
}
