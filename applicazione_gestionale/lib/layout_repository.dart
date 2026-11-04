import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

/// Lettura della mappa della spiaggia (collezione `beachLayout`).
class LayoutRepository {
  LayoutRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  static LayoutRepository? _instance;
  static LayoutRepository get instance => _instance ??= LayoutRepository();
  @visibleForTesting
  static set instance(LayoutRepository repository) => _instance = repository;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get db => _firestore ?? FirebaseFirestore.instance;

  Future<List<BeachSector>> loadSectors() async {
    final snapshot = await db.collection('beachLayout').get();
    final sectors = <BeachSector>[];
    for (final doc in snapshot.docs) {
      try {
        sectors.add(BeachSector.fromMap(doc.data()));
      } catch (e) {
        debugPrint('Settore ${doc.id} non valido: $e');
      }
    }
    return BeachSector.sorted(sectors);
  }
}
