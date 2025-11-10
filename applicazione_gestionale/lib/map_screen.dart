import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- MODELLI DATI (NUOVA STRUTTURA) ---
class Booking {
  final String id;
  final String umbrellaId;
  final String clientName;
  final DateTime startDate;
  final DateTime endDate;
  final String notes;
  final bool arrived;

  Booking({
    required this.id,
    required this.umbrellaId,
    required this.clientName,
    required this.startDate,
    required this.endDate,
    this.notes = '',
    this.arrived = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'umbrellaId': umbrellaId,
      'clientName': clientName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'notes': notes,
      'arrived': arrived,
    };
  }

  factory Booking.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> map = doc.data() as Map<String, dynamic>;
    return Booking(
      id: doc.id,
      umbrellaId: map['umbrellaId'] ?? '',
      clientName: map['clientName'] ?? '',
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: (map['endDate'] as Timestamp).toDate(),
      notes: map['notes'] ?? '',
      arrived: map['arrived'] ?? false,
    );
  }
}

class Umbrella {
  final String id;
  final String sectorName;
  final int index;

  Umbrella({
    required this.id,
    required this.sectorName,
    required this.index,
  });
}

class BeachSector {
  final String name;
  final List<Umbrella> umbrellas;
  final int crossAxisCount;
  final int rows;
  final List<int> walkwayColumns;

  BeachSector({
    required this.name,
    required this.umbrellas,
    required this.crossAxisCount,
    required this.rows,
    this.walkwayColumns = const [],
  });
}

// --- SCHERMATA DELLA MAPPA ---
class MapScreen extends StatefulWidget {
  final String? highlightUmbrellaId;
  final DateTimeRange? filterDateRange;
  final List<BeachSector> beachSectors;

  const MapScreen({
    super.key,
    this.highlightUmbrellaId,
    this.filterDateRange,
    required this.beachSectors,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String? _selectedSectorName;
  DateTimeRange? _filterDateRange;
  Booking? _bookingToMove;
  bool _isHighlightPending = true; // Flag per gestire il popup automatico

  final CollectionReference bookingsCollection = FirebaseFirestore.instance.collection('bookings');

  @override
  void initState() {
    super.initState();
    _filterDateRange = widget.filterDateRange;
    if (widget.beachSectors.length == 1) {
      _selectedSectorName = widget.beachSectors.first.name;
    }
  }

  Booking? _findBookingFor(Umbrella umbrella, DateTimeRange? range, List<Booking> allBookings) {
    if (range == null) return null;
    final filterStart = DateTime(range.start.year, range.start.month, range.start.day);
    final filterEnd = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1));

    for (final booking in allBookings) {
      if (booking.umbrellaId == umbrella.id) {
        final bookingStart = DateTime(booking.startDate.year, booking.startDate.month, booking.startDate.day);
        final bookingEnd = DateTime(booking.endDate.year, booking.endDate.month, booking.endDate.day).add(const Duration(days: 1));
        if (bookingStart.isBefore(filterEnd) && bookingEnd.isAfter(filterStart)) return booking;
      }
    }
    return null;
  }

  void _showBookingDialog(Umbrella umbrella, Booking? currentBooking) {
    final nameController = TextEditingController(text: currentBooking?.clientName);
    final notesController = TextEditingController(text: currentBooking?.notes);
    DateTime startDate = _filterDateRange?.start ?? DateTime.now();
    DateTime endDate = _filterDateRange?.end ?? startDate;

    if (currentBooking != null) {
      startDate = currentBooking.startDate;
      endDate = currentBooking.endDate;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Prenotazione Ombrellone ${umbrella.id}'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome Cliente'), textCapitalization: TextCapitalization.words),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Dal: ${DateFormat('dd/MM/yy').format(startDate)}'),
                    ElevatedButton(child: const Text('Seleziona'), onPressed: () async {
                        final date = await showDatePicker(context: context, initialDate: startDate, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (date != null) setDialogState(() { startDate = date; if (endDate.isBefore(startDate)) endDate = startDate; });
                    }),
                ]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Al: ${DateFormat('dd/MM/yy').format(endDate)}'),
                    ElevatedButton(child: const Text('Seleziona'), onPressed: () async {
                        final date = await showDatePicker(context: context, initialDate: endDate, firstDate: startDate, lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (date != null) setDialogState(() => endDate = date);
                    }),
                ]),
                const SizedBox(height: 16),
                TextField(controller: notesController, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()), maxLines: 3),
              ]),
            ),
            actions: [
              if (currentBooking != null)
                TextButton(child: const Text('SPOSTA'), onPressed: () {
                    Navigator.of(context).pop();
                    setState(() => _bookingToMove = currentBooking);
                }),
              if (currentBooking != null)
                TextButton(child: const Text('CANCELLA', style: TextStyle(color: Colors.red)), onPressed: () { bookingsCollection.doc(currentBooking.id).delete(); Navigator.of(context).pop(); }),
              TextButton(child: const Text('ANNULLA'), onPressed: () => Navigator.of(context).pop()),
              ElevatedButton(child: Text(currentBooking == null ? 'SALVA' : 'AGGIORNA'), onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    final data = {
                      'umbrellaId': umbrella.id,
                      'clientName': nameController.text,
                      'startDate': Timestamp.fromDate(startDate),
                      'endDate': Timestamp.fromDate(endDate),
                      'notes': notesController.text,
                      'arrived': currentBooking?.arrived ?? false,
                    };
                    if (currentBooking != null) bookingsCollection.doc(currentBooking.id).update(data); else bookingsCollection.add(data);
                    Navigator.of(context).pop();
                  }
              }),
            ],
          );
        });
      },
    ).then((_) => setState(() => _isHighlightPending = false)); // Resetta il flag quando il dialogo si chiude
  }

  void _moveBooking(Umbrella newUmbrella) {
    if (_bookingToMove == null) return;
    bookingsCollection.doc(_bookingToMove!.id).update({'umbrellaId': newUmbrella.id});
    setState(() => _bookingToMove = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Prenotazione spostata all\'ombrellone ${newUmbrella.id}')));
  }

  void _showFreeUmbrellas(List<Booking> allBookings) {
    if (_filterDateRange == null) return;

    final allUmbrellas = widget.beachSectors.expand((s) => s.umbrellas).toList();
    final freeUmbrellas = allUmbrellas.where((u) => _findBookingFor(u, _filterDateRange, allBookings) == null).toList();

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
              Text('Ombrelloni liberi dal ${DateFormat('dd/MM/yy').format(_filterDateRange!.start)} al ${DateFormat('dd/MM/yy').format(_filterDateRange!.end)}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Expanded(
                child: freeUmbrellas.isEmpty
                  ? const Center(child: Text('Nessun ombrellone libero nel periodo selezionato.'))
                  : ListView.builder(
                      itemCount: sortedSectors.length,
                      itemBuilder: (context, index) {
                        final sectorName = sortedSectors[index];
                        final umbrellasInSector = groupedBySector[sectorName]!;
                        umbrellasInSector.sort((a,b) => a.index.compareTo(b.index)); 

                        return ExpansionTile(
                          title: Text(sectorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          initiallyExpanded: true,
                          children: umbrellasInSector.map((u) => ListTile(title: Text('Ombrellone ${u.id}'), onTap: () {
                              Navigator.of(context).pop();
                              _showBookingDialog(u, null);
                          })).toList(),
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
        title: const Text('Mappa Spiaggia'), 
        actions: isMoveMode ? [] : [ // Nasconde i pulsanti in modalità spostamento
          DropdownButton<String>(
            value: _selectedSectorName,
            hint: const Text('Settore', style: TextStyle(color: Colors.black87)),
            onChanged: (String? newValue) => setState(() => _selectedSectorName = newValue),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('Tutti')),
              ...widget.beachSectors.map((s) => DropdownMenuItem<String>(value: s.name, child: Text(s.name))),
            ],
          ),
          const SizedBox(width: 8),
      ]),
      body: Column(
        children: [
          if (isMoveMode)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade200,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.move_down, size: 20), const SizedBox(width: 8), Flexible(child: Text('SPOSTA: Seleziona un ombrellone libero', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900), overflow: TextOverflow.ellipsis))]),
            ),
          if (_filterDateRange != null && !isMoveMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.green.shade100,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Periodo: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                Text('${DateFormat('dd/MM/yyyy').format(_filterDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_filterDateRange!.end)}', style: TextStyle(color: Colors.green.shade900)),
              ]),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: bookingsCollection.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('Errore di connessione.'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                final allBookings = snapshot.data!.docs.map((doc) => Booking.fromFirestore(doc)).toList();
                
                if (widget.highlightUmbrellaId != null && _isHighlightPending) {
                  final umbrellaToHighlight = widget.beachSectors.expand((s) => s.umbrellas).firstWhere((u) => u.id == widget.highlightUmbrellaId, orElse: () => Umbrella(id: '', sectorName: '', index: -1));
                  if (umbrellaToHighlight.id.isNotEmpty) {
                    final bookingToHighlight = _findBookingFor(umbrellaToHighlight, widget.filterDateRange, allBookings);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showBookingDialog(umbrellaToHighlight, bookingToHighlight);
                    });
                  }
                }

                final visibleSectors = _selectedSectorName == null ? widget.beachSectors : widget.beachSectors.where((s) => s.name == _selectedSectorName).toList();

                return InteractiveViewer(
                  minScale: 0.2, maxScale: 5.0,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: visibleSectors.map((sector) => _buildSector(sector, allBookings)).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isMoveMode
        ? FloatingActionButton(onPressed: () => setState(() => _bookingToMove = null), tooltip: 'Annulla Spostamento', backgroundColor: Colors.red, child: const Icon(Icons.close))
        : FloatingActionButton.extended(onPressed: () {
            if (_filterDateRange == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleziona un periodo di date prima di cercare i liberi!')));
                return;
            }
            bookingsCollection.get().then((snapshot) {
                final allBookings = snapshot.docs.map((doc) => Booking.fromFirestore(doc)).toList();
                _showFreeUmbrellas(allBookings);
            });
          }, label: const Text('Suggerisci'), icon: const Icon(Icons.lightbulb_outline)),
    );
  }

  Widget _buildSector(BeachSector sector, List<Booking> allBookings) {
    final umbrellaMap = {for (var u in sector.umbrellas) u.index: u};
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (sector.name == 'Mare')
            Container(height: 50, margin: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Colors.blue.shade100, border: Border.symmetric(horizontal: BorderSide(color: Colors.blue.shade300, width: 2))), child: const Center(child: Text('MARE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)))),
        Text(sector.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: sector.crossAxisCount, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: sector.rows * sector.crossAxisCount,
          itemBuilder: (context, index) {
            final col = index % sector.crossAxisCount;
            if (sector.walkwayColumns.contains(col)) return Container(decoration: BoxDecoration(color: Colors.brown.shade200, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.square_foot_rounded, size: 20, color: Colors.black54));

            final umbrella = umbrellaMap[index];
            if (umbrella == null) return Container(decoration: BoxDecoration(color: Colors.grey.shade200.withOpacity(0.5), borderRadius: BorderRadius.circular(8)));

            final booking = _findBookingFor(umbrella, _filterDateRange, allBookings);
            return _buildUmbrella(umbrella, booking);
          },
        ),
      ]),
    );
  }

  Widget _buildUmbrella(Umbrella umbrella, Booking? booking) {
    final isBooked = booking != null;
    final color = isBooked ? Colors.red : Colors.green;
    bool isMoveMode = _bookingToMove != null;

    return GestureDetector(
      onTap: () {
        if (isMoveMode) {
          if (!isBooked) _moveBooking(umbrella);
        } else {
          if (_filterDateRange == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleziona un periodo di date prima di prenotare!'))); return; }
          _showBookingDialog(umbrella, booking);
        }
      },
      child: Opacity(
        opacity: (isMoveMode && isBooked) ? 0.3 : 1.0,
        child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)), child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(umbrella.id, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
      ),
    );
  }
}

// --- NUOVO BOOKING SEARCH DELEGATE ---
enum SearchMode { byName, byDate }

class BookingSearchDelegate extends SearchDelegate<Booking?> {
  final List<Booking> allBookings;
  final List<Umbrella> allUmbrellas;
  SearchMode _searchMode = SearchMode.byName;
  DateTime _selectedDate = DateTime.now();

  BookingSearchDelegate(this.allBookings, this.allUmbrellas);

  @override
  String get searchFieldLabel => 'Cerca per nome o data...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return StatefulBuilder(builder: (BuildContext context, StateSetter setState) {
      Widget searchControls;
      if (_searchMode == SearchMode.byName) {
        searchControls = Padding(padding: const EdgeInsets.all(16.0), child: Text(query.isEmpty ? 'Digita il nome del cliente...' : 'Risultati per "$query"'));
      } else {
        searchControls = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Prenotazioni del: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'),
            ElevatedButton(child: const Text('Cambia Data'), onPressed: () async {
              final pickedDate = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (pickedDate != null) setState(() => _selectedDate = pickedDate);
            }),
          ]),
        );
      }

      return Column(children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: DropdownButton<SearchMode>(value: _searchMode, isExpanded: true, items: const [DropdownMenuItem(value: SearchMode.byName, child: Text('Cerca per Nome')),
              DropdownMenuItem(value: SearchMode.byDate, child: Text('Cerca per Data'))], onChanged: (SearchMode? newValue) {
            if (newValue != null) setState(() { _searchMode = newValue; query = ''; });
          }),
        ),
        const Divider(),
        searchControls,
        const Divider(),
        Expanded(child: _buildResultsList(context)),
      ]);
    });
  }

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  Widget _buildResultsList(BuildContext context) {
    Iterable<Booking> results;

    if (_searchMode == SearchMode.byName) {
      if (query.isEmpty) return const Center(child: Text('Inizia a digitare un nome per cercare.'));
      results = allBookings.where((b) => b.clientName.toLowerCase().contains(query.toLowerCase()));
    } else {
      final searchDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      results = allBookings.where((b) {
        final startDay = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
        final endDay = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);
        return !(searchDay.isBefore(startDay) || searchDay.isAfter(endDay));
      });
    }

    if (results.isEmpty) return const Center(child: Text('Nessuna prenotazione trovata.'));

    return ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
      final booking = results.elementAt(index);
      return ListTile(
        title: Text('${booking.clientName} - Ombrellone ${booking.umbrellaId}'),
        subtitle: Text('Periodo: ${DateFormat('dd/MM/yy').format(booking.startDate)} - ${DateFormat('dd/MM/yy').format(booking.endDate)}'),
        onTap: () => close(context, booking),
      );
    });
  }
}
