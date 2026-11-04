import 'package:flutter/material.dart';

import 'models.dart';

/// I settori (Mare, Tende, Dietro) sono separati: spostare una prenotazione in un
/// settore diverso richiede una conferma esplicita.
/// Restituisce true se si può procedere.
Future<bool> confirmSectorChange(BuildContext context, Booking booking, Umbrella target, {bool extension = false}) async {
  if (booking.sectorName == target.sectorName) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Cambiare settore?'),
      content: Text(
        '${booking.clientName} è nel settore ${booking.sectorName}.\n\n'
        '${extension ? 'Vuoi mettere i giorni extra' : 'Vuoi spostarlo'} in ${target.sectorName}, ombrellone ${target.simpleId}?\n\n'
        'Ricorda che settori diversi possono avere prezzi diversi.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('NO')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text('SÌ, IN ${target.sectorName.toUpperCase()}')),
      ],
    ),
  );
  return ok == true;
}
