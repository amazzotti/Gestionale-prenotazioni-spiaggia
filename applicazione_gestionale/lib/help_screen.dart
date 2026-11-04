import 'package:flutter/material.dart';

import 'app_version.dart';

/// Argomenti della guida.
enum HelpTopic { inizio, mappa, prenotazione, suggeritore, planner, arrivi, incassi, telefoni, stagione }

class _Topic {
  final HelpTopic id;
  final IconData icon;
  final String title;
  final List<String> steps;
  const _Topic(this.id, this.icon, this.title, this.steps);
}

const _topics = <_Topic>[
  _Topic(HelpTopic.inizio, Icons.home_outlined, 'Per iniziare', [
    'In alto nella home vedi il riepilogo di oggi: ombrelloni occupati, arrivi e partenze.',
    '"Nuova Prenotazione": scegli le date, poi l\'app ti consiglia dove metterla.',
    '"Mappa di Oggi" e "Planner" ti fanno vedere la spiaggia; "Cerca" trova un cliente per nome, telefono o numero di ombrellone.',
    'In fondo alla home c\'è la versione dell\'app (es. V1.0.0).',
  ]),
  _Topic(HelpTopic.mappa, Icons.map_outlined, 'La mappa', [
    'Verde = libero, rosso = occupato nel periodo che stai guardando.',
    'Sul quadrato vedi il periodo della prenotazione (data di arrivo sopra, partenza sotto).',
    'Il bollino arancione con l\'euro vuol dire che c\'è ancora da incassare, il bollino verde con la spunta che il cliente è arrivato.',
    'Le frecce accanto alla data cambiano giorno, OGGI torna a oggi; toccando la data puoi scegliere un periodo di più giorni.',
    'Tocco su un ombrellone: apri la prenotazione o ne crei una nuova.',
    'Pressione lunga su un ombrellone: vedi chi c\'era PRIMA, chi c\'è NEL PERIODO e chi arriva DOPO.',
    'Con due dita puoi ingrandire la mappa.',
  ]),
  _Topic(HelpTopic.prenotazione, Icons.edit_note, 'La scheda della prenotazione', [
    'Scrivi il nome: se il cliente è già venuto, l\'app lo propone e ricorda il suo telefono.',
    'Con il telefono compaiono i tasti Chiama e WhatsApp; su WhatsApp il riepilogo della prenotazione è già scritto.',
    'Il riquadro Prima / Dopo ti dice chi c\'è su quell\'ombrellone prima e dopo le date scelte.',
    'Prezzo, acconto e "Saldato": l\'app calcola quanto resta da incassare.',
    'Il tasto arancione SPOSTA porta la prenotazione su un altro ombrellone; "Allunga altrove" compare se i giorni in più sono occupati.',
    'Il cestino elimina dopo una conferma; per qualche secondo puoi premere ANNULLA.',
    'L\'app non salva mai due prenotazioni sullo stesso ombrellone negli stessi giorni.',
  ]),
  _Topic(HelpTopic.suggeritore, Icons.lightbulb_outline, 'Il suggeritore "Dove la metto?"', [
    'Si apre da solo dopo "Nuova Prenotazione", oppure con la lampadina in alto nella mappa.',
    'Puoi scegliere il settore e scrivere il nome del cliente.',
    'Prima propone l\'ombrellone che il cliente ha già avuto, poi quelli dove la prenotazione si incastra tra due clienti senza lasciare giorni scomodi.',
    'Gli ombrelloni liberi tutta la stagione li tiene per ultimi, per chi si ferma di più.',
    'Tocca PRENOTA QUI e la scheda si apre già compilata.',
  ]),
  _Topic(HelpTopic.planner, Icons.date_range, 'Il planner (calendario)', [
    'Una riga per ombrellone, una colonna per giorno: il quadro di 4 settimane in un colpo d\'occhio.',
    'Barre rosse = prenotazioni nel periodo scelto, barre grigie = prima e dopo.',
    'Tocco su una barra per aprirla, tocco su uno spazio vuoto per prenotare da quel giorno.',
    'Per spostare: tocca la barra, poi SPOSTA, poi la riga di destinazione. Le righe verdi sono quelle libere per quelle date.',
    'Le frecce cambiano settimana; trascina col dito per scorrere.',
  ]),
  _Topic(HelpTopic.arrivi, Icons.people_outline, 'Arrivi e partenze', [
    'Chi arriva e chi parte nel giorno scelto (di default oggi).',
    'Spunta la casella quando il cliente arriva: sulla mappa compare il bollino verde.',
    'Tocca "Da incassare" per segnare il pagamento come saldato.',
  ]),
  _Topic(HelpTopic.incassi, Icons.bar_chart, 'Incassi e statistiche', [
    'Occupazione del giorno per settore, con le frecce per cambiare giorno.',
    'Totale incassato e da incassare della stagione.',
    'Elenco di chi deve ancora pagare: tocca l\'importo per segnarlo come saldato.',
  ]),
  _Topic(HelpTopic.telefoni, Icons.smartphone, 'Telefoni e sicurezza', [
    'Non serve nessuna password: ogni telefono va approvato una volta sola.',
    'Un telefono nuovo mostra un codice e il tasto "Chiedi l\'accesso".',
    'Da "Telefoni" (solo famiglia) controlli il codice e premi APPROVA: il telefono si sblocca da solo.',
    'Puoi togliere l\'accesso a un telefono perso in qualsiasi momento.',
    'Chi non è approvato non vede nessun dato.',
  ]),
  _Topic(HelpTopic.stagione, Icons.settings_backup_restore, 'Mappa e fine stagione', [
    'Editor Mappa (solo famiglia): costruisci i settori con righe, colonne e passerelle.',
    'Un ombrellone con prenotazioni non si può togliere: prima spostale.',
    'Reset Stagione cancella tutte le prenotazioni: per sicurezza devi scrivere RESET.',
  ]),
];

/// Guida dell'app: tutte le funzioni spiegate in modo semplice.
class HelpScreen extends StatelessWidget {
  final HelpTopic? initialTopic;
  const HelpScreen({super.key, this.initialTopic});

  /// Apre la guida, opzionalmente su un argomento.
  static void open(BuildContext context, [HelpTopic? topic]) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => HelpScreen(initialTopic: topic)));
  }

  @override
  Widget build(BuildContext context) {
    final topics = initialTopic == null ? _topics : [..._topics.where((t) => t.id == initialTopic), ..._topics.where((t) => t.id != initialTopic)];
    return Scaffold(
      appBar: AppBar(title: const Text('Guida'), backgroundColor: Colors.green),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final t in topics)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ExpansionTile(
                leading: Icon(t.icon, color: Colors.green.shade800),
                title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                initiallyExpanded: t.id == initialTopic,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  for (final s in t.steps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('•  ', style: TextStyle(fontSize: 16)),
                        Expanded(child: Text(s, style: const TextStyle(fontSize: 15))),
                      ]),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          const AppVersionText(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Pulsante "?" che apre la guida sull'argomento indicato.
class HelpButton extends StatelessWidget {
  final HelpTopic topic;
  final Color? color;
  const HelpButton(this.topic, {super.key, this.color});

  @override
  Widget build(BuildContext context) =>
      IconButton(icon: Icon(Icons.help_outline, color: color), tooltip: 'Guida', onPressed: () => HelpScreen.open(context, topic));
}
