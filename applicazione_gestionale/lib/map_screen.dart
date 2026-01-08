import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- MODELLI DATI ---
class Booking {
  final String id;
  final String umbrellaId;
  final String clientName;
  final DateTime startDate;
  final DateTime endDate;
  final String notes;
  final bool isCheckedIn;

  Booking({
    required this.id,
    required this.umbrellaId,
    required this.clientName,
    required this.startDate,
    required this.endDate,
    this.notes = '',
    this.isCheckedIn = false,
  });

  factory Booking.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw Exception("Dati del documento non validi");
    return Booking(
      id: doc.id,
      umbrellaId: doc.id, // L'ID del documento è l'ID univoco dell'ombrellone
      clientName: data['clientName'] ?? 'Sconosciuto',
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      notes: data['notes'] ?? '',
      isCheckedIn: data['isCheckedIn'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientName': clientName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'notes': notes,
      'isCheckedIn': isCheckedIn,
    };
  }
}

class Umbrella {
  final String id; // Es: 'Mare-50'
  final String sectorName;
  final int index;

  Umbrella({required this.id, required this.sectorName, required this.index});

  String get simpleId => id.split('-').last;
}

class BeachSector {
  final String name;
  final int rows;
  final int crossAxisCount;
  final List<Umbrella> umbrellas;
  final List<int> walkwayColumns;

  BeachSector({
    required this.name,
    required this.rows,
    required this.crossAxisCount,
    required this.umbrellas,
    required this.walkwayColumns,
  });
}

// --- SCHERMATA DELLA MAPPA ---
class MapScreen extends StatefulWidget {
  final List<BeachSector> beachSectors;
  final String? highlightUmbrellaId;
  final DateTimeRange? filterDateRange;

  const MapScreen({
    super.key,
    required this.beachSectors,
    this.highlightUmbrellaId,
    this.filterDateRange,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String? _selectedSectorName;
  DateTimeRange? _filterDateRange;
  Booking? _bookingToMove;
  bool _isHighlightPending = true;

  final CollectionReference<Map<String, dynamic>> bookingsCollection =
  FirebaseFirestore.instance.collection('bookings');

  @override
  void initState() {
    super.initState();
    _filterDateRange = widget.filterDateRange;
  }

  Booking? _findBookingFor(Umbrella umbrella, DateTimeRange? range, List<Booking> allBookings) {
    if (range == null) return null;
    try {
      // Questo confronto funziona solo se gli ID sono veramente univoci
      return allBookings.firstWhere(
            (b) =>
        b.umbrellaId == umbrella.id &&
            b.startDate.isBefore(range.end) &&
            b.endDate.isAfter(range.start),
      );
    } catch (e) {
      return null;
    }
  }

  void _showBookingDialog(Umbrella umbrella, Booking? currentBooking) {
    if (_filterDateRange == null) {
      // ... (codice invariato)
      return;
    }

    final nameController = TextEditingController(text: currentBooking?.clientName);
    final notesController = TextEditingController(text: currentBooking?.notes);
    final startDate = _filterDateRange!.start;
    final endDate = _filterDateRange!.end;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Ombrellone ${umbrella.simpleId} (${umbrella.sectorName})'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nome Cliente'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Text(
                  'Periodo: ${DateFormat('dd/MM/yyyy').format(startDate)} - ${DateFormat('dd/MM/yyyy').format(endDate)}',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            if (currentBooking != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Cancella Prenotazione',
                onPressed: () {
                  // **PUNTO CRUCIALE 1: Cancellazione**
                  // L'ID del documento DEVE essere l'ID univoco.
                  bookingsCollection.doc(currentBooking.id).delete();
                  Navigator.of(context).pop();
                },
              ),
            if (currentBooking != null && _bookingToMove == null)
              IconButton(
                icon: const Icon(Icons.move_down),
                tooltip: 'Sposta Prenotazione',
                onPressed: () {
                  setState(() => _bookingToMove = currentBooking);
                  Navigator.of(context).pop();
                },
              ),
            const Spacer(),
            TextButton(
              child: const Text('ANNULLA'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(currentBooking == null ? 'SALVA' : 'AGGIORNA'),
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  // **PUNTO CRUCIALE 2: Creazione/Aggiornamento**
                  // L'ID del documento che andiamo a scrivere è l'ID UNIVOCO dell'ombrellone.
                  final String docId = umbrella.id;

                  final bookingData = Booking(
                    id: docId,
                    umbrellaId: docId,
                    clientName: nameController.text,
                    startDate: startDate,
                    endDate: endDate,
                    notes: notesController.text,
                    isCheckedIn: currentBooking?.isCheckedIn ?? false,
                  );

                  // Usiamo .set() con l'ID univoco.
                  // Questo crea un nuovo documento con ID 'Mare-9' o 'Dietro-9',
                  // senza sovrascrivere l'altro.
                  await bookingsCollection.doc(docId).set(bookingData.toFirestore());
                  if (mounted) Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    ).then((_) => setState(() => _isHighlightPending = false));
  }

  void _moveBooking(Umbrella newUmbrella, Booking bookingToMove) {
    // **PUNTO CRUCIALE 3: Spostamento**
    final newBooking = Booking(
      id: newUmbrella.id, // Nuovo ID univoco
      umbrellaId: newUmbrella.id,
      clientName: bookingToMove.clientName,
      startDate: bookingToMove.startDate,
      endDate: bookingToMove.endDate,
      notes: bookingToMove.notes,
      isCheckedIn: bookingToMove.isCheckedIn,
    );

    FirebaseFirestore.instance.runTransaction((transaction) async {
      // Riferimento al vecchio documento (es. 'Mare-9')
      final oldDocRef = bookingsCollection.doc(bookingToMove.id);
      // Riferimento al nuovo documento (es. 'Dietro-12')
      final newDocRef = bookingsCollection.doc(newUmbrella.id);

      transaction.delete(oldDocRef);
      transaction.set(newDocRef, newBooking.toFirestore());
    }).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Prenotazione spostata all\'ombrellone ${newUmbrella.simpleId}')));
      }
    }).catchError((error) {
      // ... gestione errore
    }).whenComplete(() {
      if (mounted) setState(() => _bookingToMove = null);
    });
  }

  // ... (tutto il resto del file, da _showFreeUmbrellas in poi, rimane invariato)
  // ... (puoi copiare il resto del codice dalla risposta precedente, perché era già corretto)
  void _showFreeUmbrellas(List<Booking> allBookings) {
    if (_filterDateRange == null) return;

    final allUmbrellas = widget.beachSectors.expand((s) => s.umbrellas).toList();
    final freeUmbrellas = allUmbrellas
        .where((u) => _findBookingFor(u, _filterDateRange, allBookings) == null)
        .toList();

    final Map<String, List<Umbrella>> groupedBySector = {};
    for (final umbrella in freeUmbrellas) {
      if (!groupedBySector.containsKey(umbrella.sectorName)) {
        groupedBySector[umbrella.sectorName] = [];
      }
      groupedBySector[umbrella.sectorName]!.add(umbrella);
    }

    final sectorOrder = {'Mare': 1, 'Tende': 2, 'Dietro': 3};
    final sortedSectors = groupedBySector.keys.toList()
      ..sort((a, b) => (sectorOrder[a] ?? 99).compareTo(sectorOrder[b] ?? 99));

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ombrelloni liberi dal ${DateFormat('dd/MM/yy').format(_filterDateRange!.start)} al ${DateFormat('dd/MM/yy').format(_filterDateRange!.end)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: freeUmbrellas.isEmpty
                    ? const Center(
                    child: Text('Nessun ombrellone libero nel periodo selezionato.'))
                    : ListView.builder(
                  itemCount: sortedSectors.length,
                  itemBuilder: (context, index) {
                    final sectorName = sortedSectors[index];
                    final umbrellasInSector = groupedBySector[sectorName]!;
                    umbrellasInSector.sort(
                            (a, b) => int.parse(a.simpleId).compareTo(int.parse(b.simpleId)));

                    return ExpansionTile(
                      title: Text(sectorName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      initiallyExpanded: true,
                      children: umbrellasInSector
                          .map((u) => ListTile(
                          title: Text('Ombrellone ${u.simpleId}'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showBookingDialog(u, null);
                          }))
                          .toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMoveMode = _bookingToMove != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text(isMoveMode ? 'Sposta Prenotazione' : 'Mappa Spiaggia'),
        actions: isMoveMode
            ? []
            : [
          DropdownButton<String>(
            value: _selectedSectorName,
            hint: const Text('Settore', style: TextStyle(color: Colors.white)),
            iconEnabledColor: Colors.white,
            dropdownColor: Colors.green.shade700,
            style: const TextStyle(color: Colors.white),
            onChanged: (String? newValue) =>
                setState(() => _selectedSectorName = newValue),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('Tutti')),
              ...widget.beachSectors.map((s) =>
                  DropdownMenuItem<String>(
                      value: s.name, child: Text(s.name))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (isMoveMode)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade200,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.move_down, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(
                            'SPOSTA: Seleziona un ombrellone libero',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900),
                            overflow: TextOverflow.ellipsis))
                  ]),
            ),
          if (_filterDateRange != null && !isMoveMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.green.shade100,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Periodo: ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900)),
                Text(
                    '${DateFormat('dd/MM/yyyy').format(_filterDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_filterDateRange!.end)}',
                    style: TextStyle(color: Colors.green.shade900)),
              ]),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: bookingsCollection.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Errore di connessione.'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allBookings = snapshot.data!.docs.map((doc) => Booking.fromFirestore(doc)).toList();

                if (widget.highlightUmbrellaId != null && _isHighlightPending) {
                  try {
                    final umbrellaToHighlight = widget.beachSectors
                        .expand((s) => s.umbrellas)
                        .firstWhere((u) => u.id == widget.highlightUmbrellaId);
                    final bookingToHighlight = _findBookingFor(
                        umbrellaToHighlight, widget.filterDateRange, allBookings);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _showBookingDialog(umbrellaToHighlight, bookingToHighlight);
                      }
                    });
                  } catch (e) {
                    // Ombrellone non trovato, ignora
                  }
                }

                final visibleSectors = _selectedSectorName == null
                    ? widget.beachSectors
                    : widget.beachSectors
                    .where((s) => s.name == _selectedSectorName)
                    .toList();

                return InteractiveViewer(
                  minScale: 0.2,
                  maxScale: 5.0,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: visibleSectors
                          .map((sector) => _buildSector(sector, allBookings))
                          .toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isMoveMode
          ? FloatingActionButton.extended(
          onPressed: () => setState(() => _bookingToMove = null),
          label: const Text("Annulla"),
          tooltip: 'Annulla Spostamento',
          backgroundColor: Colors.red,
          icon: const Icon(Icons.close))
          : FloatingActionButton.extended(
          onPressed: () {
            if (_filterDateRange == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Seleziona un periodo prima di cercare i liberi!')));
              return;
            }
            final streamProvider = bookingsCollection.snapshots().first;
            streamProvider.then((snapshot) {
              final allBookings = snapshot.docs.map((doc) => Booking.fromFirestore(doc)).toList();
              _showFreeUmbrellas(allBookings);
            });
          },
          label: const Text('Liberi'),
          icon: const Icon(Icons.lightbulb_outline)),
    );
  }

  Widget _buildSector(BeachSector sector, List<Booking> allBookings) {
    final umbrellaMap = {for (var u in sector.umbrellas) u.index: u};
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sector.name,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        if (sector.name == 'Mare')
          Container(
              height: 50,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  border: Border.symmetric(
                      horizontal:
                      BorderSide(color: Colors.blue.shade300, width: 2))),
              child: const Center(
                  child: Text('MARE',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey)))),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: sector.crossAxisCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8),
          itemCount: sector.rows * sector.crossAxisCount,
          itemBuilder: (context, index) {
            final col = index % sector.crossAxisCount;
            if (sector.walkwayColumns.contains(col)) {
              return Container(
                  decoration: BoxDecoration(
                      color: Colors.brown.shade200,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.square_foot_rounded,
                      size: 20, color: Colors.black54));
            }

            final umbrella = umbrellaMap[index];
            if (umbrella == null) {
              return Container(
                  decoration: BoxDecoration(
                      color: Colors.grey.shade200.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8)));
            }

            final booking = _findBookingFor(umbrella, _filterDateRange, allBookings);
            return _buildUmbrella(umbrella, booking);
          },
        ),
      ]),
    );
  }

  Widget _buildUmbrella(Umbrella umbrella, Booking? booking) {
    final isBooked = booking != null;
    final color = isBooked ? Colors.red.shade400 : Colors.green.shade400;
    bool isMoveMode = _bookingToMove != null;

    return GestureDetector(
      onTap: () {
        if (isMoveMode) {
          if (!isBooked) _moveBooking(umbrella, _bookingToMove!);
        } else {
          _showBookingDialog(umbrella, booking);
        }
      },
      child: Opacity(
        opacity: (isMoveMode && isBooked) ? 0.3 : 1.0,
        child: Container(
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(8)),
            child: Center(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(umbrella.simpleId, // Mostra solo il numero
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18))))),
      ),
    );
  }
}

