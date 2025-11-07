import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- MODELLI DATI ---
class Booking {
  final String clientName;
  final DateTime startDate;
  final DateTime endDate;
  final String notes;
  final bool arrived;

  Booking({
    required this.clientName,
    required this.startDate,
    required this.endDate,
    this.notes = '',
    this.arrived = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'clientName': clientName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'notes': notes,
      'arrived': arrived,
    };
  }

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      clientName: map['clientName'],
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
  Booking? booking;

  Umbrella({
    required this.id,
    required this.sectorName,
    required this.index,
    this.booking,
  });

  bool get isBooked => booking != null;

  bool isBookedDuring(DateTimeRange range) {
    if (!isBooked) return false;
    final bookingStart = DateTime(booking!.startDate.year, booking!.startDate.month, booking!.startDate.day);
    final bookingEnd = DateTime(booking!.endDate.year, booking!.endDate.month, booking!.endDate.day).add(const Duration(days: 1));
    final filterStart = DateTime(range.start.year, range.start.month, range.start.day);
    final filterEnd = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1));
    return bookingStart.isBefore(filterEnd) && filterStart.isBefore(bookingEnd);
  }
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
  bool _isHighlightPending = true;

  final CollectionReference bookingsCollection = FirebaseFirestore.instance.collection('bookings');

  @override
  void initState() {
    super.initState();
    _filterDateRange = widget.filterDateRange;
    if (widget.beachSectors.length == 1) {
      _selectedSectorName = widget.beachSectors.first.name;
    }
  }

  Future<void> _saveBooking(Umbrella umbrella, Booking newBooking) async {
    await bookingsCollection.doc(umbrella.id).set(newBooking.toMap());
  }

  Future<void> _deleteBooking(Umbrella umbrella) async {
    await bookingsCollection.doc(umbrella.id).delete();
  }

  void _showBookingDialog(Umbrella umbrella, Booking? currentBooking) {
    final nameController = TextEditingController(text: currentBooking?.clientName);
    final notesController = TextEditingController(text: currentBooking?.notes);
    DateTime startDate = currentBooking?.startDate ?? _filterDateRange?.start ?? DateTime.now();
    DateTime endDate = currentBooking?.endDate ?? _filterDateRange?.end ?? startDate;

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Dal: ${DateFormat('dd/MM/yy').format(startDate)}'),
                    ElevatedButton(
                      child: const Text('Seleziona'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          setDialogState(() {
                            startDate = date;
                            if (endDate.isBefore(startDate)) endDate = startDate;
                          });
                        }
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Al: ${DateFormat('dd/MM/yy').format(endDate)}'),
                    ElevatedButton(
                      child: const Text('Seleziona'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: endDate,
                          firstDate: startDate,
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) setDialogState(() => endDate = date);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                  maxLines: 3,
                ),
              ]),
            ),
            actions: [
              if (currentBooking != null)
                TextButton(
                  child: const Text('CANCELLA', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    _deleteBooking(umbrella);
                    Navigator.of(context).pop();
                  },
                ),
              TextButton(child: const Text('ANNULLA'), onPressed: () => Navigator.of(context).pop()),
              ElevatedButton(
                child: const Text('SALVA'),
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    final newBooking = Booking(
                      clientName: nameController.text, startDate: startDate, endDate: endDate, notes: notesController.text,
                    );
                    _saveBooking(umbrella, newBooking);
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mappa Spiaggia'),
        actions: [
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
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: bookingsCollection.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Errore di connessione.'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final bookingsMap = <String, Booking>{};
          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              try {
                bookingsMap[doc.id] = Booking.fromMap(doc.data() as Map<String, dynamic>);
              } catch (e) { /* Ignora */ }
            }
          }

          final visibleSectors = _selectedSectorName == null
              ? widget.beachSectors
              : widget.beachSectors.where((s) => s.name == _selectedSectorName).toList();

          return InteractiveViewer(
            minScale: 0.2,
            maxScale: 5.0,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: visibleSectors.map((sector) {
                  return Column(
                    children: [
                      if (sector.name == 'Mare')
                        Container(
                          height: 50,
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            border: Border.symmetric(horizontal: BorderSide(color: Colors.blue.shade300, width: 2)),
                          ),
                          child: const Center(child: Text('MARE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))), 
                        ),
                      _buildSector(sector, bookingsMap),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSector(BeachSector sector, Map<String, Booking> bookingsMap) {
    final umbrellaMap = {for (var u in sector.umbrellas) u.index: u};

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sector.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: sector.crossAxisCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: sector.rows * sector.crossAxisCount,
          itemBuilder: (context, index) {
            final col = index % sector.crossAxisCount;
            if (sector.walkwayColumns.contains(col)) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.brown.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.square_foot_rounded, size: 20, color: Colors.black54),
              );
            }

            final umbrella = umbrellaMap[index];
            if (umbrella == null) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }

            final booking = bookingsMap[umbrella.id];
            return _buildUmbrella(umbrella, booking);
          },
        ),
      ]),
    );
  }

  Widget _buildUmbrella(Umbrella umbrella, Booking? booking) {
    umbrella.booking = booking;
    bool isConsideredBooked = _filterDateRange != null && umbrella.isBookedDuring(_filterDateRange!);
    final color = isConsideredBooked ? Colors.red : Colors.green;

    return GestureDetector(
      onTap: () => _showBookingDialog(umbrella, booking),
      child: Opacity(
        opacity: _filterDateRange == null ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Center(
            child: FittedBox( // --- Soluzione per il testo!
              fit: BoxFit.scaleDown,
              child: Text(umbrella.id, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
    );
  }
}

class BookingSearchDelegate extends SearchDelegate<Umbrella?> {
  final List<Umbrella> allUmbrellas;
  SearchMode _searchMode = SearchMode.byName;
  DateTime _selectedDate = DateTime.now();

  BookingSearchDelegate(this.allUmbrellas);

  @override
  String get searchFieldLabel => 'Cerca...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (_searchMode == SearchMode.byDate) return [];
    return [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        Widget searchControls;
        if (_searchMode == SearchMode.byName) {
          searchControls = const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Digita il nome del cliente nella barra in alto.'),
          );
        } else {
          searchControls = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Prenotazioni del: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'),
                ElevatedButton(
                  child: const Text('Cambia Data'),
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                        context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                    if (pickedDate != null) setState(() => _selectedDate = pickedDate);
                  },
                )
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: DropdownButton<SearchMode>(
                value: _searchMode,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: SearchMode.byName, child: Text('Cerca per Nome')),
                  DropdownMenuItem(value: SearchMode.byDate, child: Text('Cerca per Data')),
                ],
                onChanged: (SearchMode? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _searchMode = newValue;
                      query = '';
                    });
                  }
                },
              ),
            ),
            const Divider(),
            searchControls,
            const Divider(),
            Expanded(child: _buildResultsList(context)),
          ],
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return buildSuggestions(context);
  }

  Widget _buildResultsList(BuildContext context) {
    final bookedUmbrellas = allUmbrellas.where((u) => u.booking != null);
    final Iterable<Umbrella> results;

    if (_searchMode == SearchMode.byName) {
      if (query.isEmpty) return const Center(child: Text('Inizia a digitare un nome...'));
      results = bookedUmbrellas.where((u) => u.booking!.clientName.toLowerCase().contains(query.toLowerCase()));
    } else {
      final searchDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      results = bookedUmbrellas.where((u) {
        final booking = u.booking!;
        final startDay = DateTime(booking.startDate.year, booking.startDate.month, booking.startDate.day);
        final endDay = DateTime(booking.endDate.year, booking.endDate.month, booking.endDate.day);
        return !(searchDay.isBefore(startDay) || searchDay.isAfter(endDay));
      });
    }

    if (results.isEmpty) return const Center(child: Text('Nessuna prenotazione trovata.'));

    return ListView(children: results.map((u) => _buildSearchResultTile(context, u)).toList());
  }

  Widget _buildSearchResultTile(BuildContext context, Umbrella u) {
    final booking = u.booking!;
    return ListTile(
      title: Text('${booking.clientName} - Ombrellone ${u.id}'),
      subtitle: Text(
          'Settore: ${u.sectorName} | Periodo: ${DateFormat('dd/MM/yy').format(booking.startDate)} - ${DateFormat('dd/MM/yy').format(booking.endDate)}'),
      onTap: () => close(context, u),
    );
  }
}

enum SearchMode { byName, byDate }
