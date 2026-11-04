import 'package:flutter/material.dart';

import 'availability.dart';
import 'models.dart';

/// Un ombrellone consigliato per una nuova prenotazione, con il motivo.
class UmbrellaSuggestion {
  final Umbrella umbrella;

  /// Punteggio: più basso = consiglio migliore.
  final int score;

  /// Motivi in italiano, il primo è il principale.
  final List<String> reasons;

  /// true se il cliente ha già avuto questo ombrellone in stagione.
  final bool isHabitual;

  const UmbrellaSuggestion({required this.umbrella, required this.score, required this.reasons, this.isHabitual = false});
}

/// Quanti giorni liberi "contano" al massimo: oltre, un buco vale come "tutto libero".
const int _maxGap = 30;

/// Suggeritore: dove conviene mettere una prenotazione per queste date.
///
/// Considera solo gli ombrelloni liberi per TUTTO il periodo e li ordina così:
/// 1. l'ombrellone che il cliente ha già avuto in stagione (se si indica il nome);
/// 2. il "miglior incastro": prima gli ombrelloni dove la prenotazione si attacca
///    al cliente precedente E al successivo, poi quelli dove si attacca da un lato,
///    poi quelli con il buco più stretto (meno giorni scomodi da riempire).
///    Gli ombrelloni completamente liberi restano per ultimi, disponibili per chi si
///    ferma di più;
/// 3. a parità, l'ordine della mappa (settore, poi posizione).
///
/// [sectorName] limita la ricerca a un settore (null = tutti).
List<UmbrellaSuggestion> suggestUmbrellas({
  required DateTimeRange range,
  required List<BeachSector> sectors,
  required Iterable<Booking> bookings,
  String? sectorName,
  String? clientName,
  int limit = 5,
}) {
  final all = bookings.toList();
  final client = clientName?.trim().toLowerCase() ?? '';
  final habitual = client.isEmpty
      ? const <String>{}
      : all.where((b) => b.clientName.trim().toLowerCase() == client).map((b) => b.umbrellaId).toSet();

  final result = <(UmbrellaSuggestion, int, int)>[]; // suggerimento, ordine settore, posizione
  for (final sector in BeachSector.sorted(sectors)) {
    if (sectorName != null && sector.name != sectorName) continue;
    final sectorRank = BeachSector.sectorOrder[sector.name] ?? 99;
    for (final u in sector.umbrellas) {
      final t = umbrellaTimeline(u.id, range, all);
      if (t.inPeriod.isNotEmpty) continue; // occupato in almeno un giorno

      final before = t.freeDaysBefore;
      final after = t.freeDaysAfter;
      final gapBefore = before == null ? _maxGap : (before > _maxGap ? _maxGap : before);
      final gapAfter = after == null ? _maxGap : (after > _maxGap ? _maxGap : after);
      final isHabitual = habitual.contains(u.id);
      final attachedSides = (before == 0 ? 1 : 0) + (after == 0 ? 1 : 0);
      final score = (2 - attachedSides) * 100 + gapBefore + gapAfter - (isHabitual ? 1000 : 0);

      final reasons = <String>[];
      if (isHabitual) reasons.add('${clientName!.trim()} ha già avuto questo ombrellone');
      if (before == 0 && after == 0) {
        reasons.add('Incastro perfetto: riempie esattamente il buco tra ${t.previous!.clientName} e ${t.next!.clientName}');
      } else if (before == 0) {
        reasons.add('Subito dopo ${t.previous!.clientName}${after == null ? '' : ', poi ${freeDaysText(after)} prima di ${t.next!.clientName}'}');
      } else if (after == 0) {
        reasons.add('Subito prima di ${t.next!.clientName}${before == null ? '' : ', con ${freeDaysText(before)} dopo ${t.previous!.clientName}'}');
      } else if (before == null && after == null) {
        reasons.add('Libero per tutta la stagione');
      } else {
        final parts = <String>[
          if (before != null) '${freeDaysText(before)} prima',
          if (after != null) '${freeDaysText(after)} dopo',
        ];
        reasons.add('Lascia ${parts.join(' e ')}');
      }
      result.add((UmbrellaSuggestion(umbrella: u, score: score, reasons: reasons, isHabitual: isHabitual), sectorRank, u.index));
    }
  }
  result.sort((a, b) {
    final byScore = a.$1.score.compareTo(b.$1.score);
    if (byScore != 0) return byScore;
    final bySector = a.$2.compareTo(b.$2);
    return bySector != 0 ? bySector : a.$3.compareTo(b.$3);
  });
  return result.take(limit).map((e) => e.$1).toList();
}
