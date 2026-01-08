import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  factory Booking.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> map = doc.data() as Map<String, dynamic>;
    return Booking(
      id: doc.id,
      umbrellaId: map['umbrellaId'] ?? doc.id,
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
  Umbrella({required this.id, required this.sectorName, required this.index});
  String get simpleId {
    if (id.startsWith('Tende-')) {
      return id.replaceFirst('Tende-', '');
    }
    return id.split('-').last;
  }
}

class BeachSector {
  final String name;
  final List<Umbrella> umbrellas;
  final int crossAxisCount;
  final int rows;
  final List<int> walkwayColumns;
  BeachSector({required this.name, required this.umbrellas, required this.crossAxisCount, required this.rows, this.walkwayColumns = const []});
}

class MapScreen extends StatefulWidget {
  final String? highlightUmbrellaId;
  final DateTimeRange? filterDateRange;
  final List<BeachSector> beachSectors;
  const MapScreen({super.key, this.highlightUmbrellaId, this.filterDateRange, required this.beachSectors});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  DateTimeRange? _filterDateRange;
  Booking? _bookingToMove;
  bool _isHighlightPending = true;

  final CollectionReference bookingsCollection = FirebaseFirestore.instance.collection('bookings');

  @override
  void initState() {
    super.initState();
    _filterDateRange = widget.filterDateRange;
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
    DateTime startDate = currentBooking?.startDate ?? _filterDateRange?.start ?? DateTime.now();
    DateTime endDate = currentBooking?.endDate ?? _filterDateRange?.end ?? startDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Prenotazione Ombrellone ${umbrella.simpleId} (${umbrella.sectorName})'),
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
              if (currentBooking != null) TextButton(child: const Text('SPOSTA'), onPressed: () { Navigator.of(context).pop(); setState(() => _bookingToMove = currentBooking); }),
              if (currentBooking != null) TextButton(child: const Text('CANCELLA', style: TextStyle(color: Colors.red)), onPressed: () { bookingsCollection.doc(currentBooking.id).delete(); Navigator.of(context).pop(); }),
              TextButton(child: const Text('ANNULLA'), onPressed: () => Navigator.of(context).pop()),
              ElevatedButton(
                child: Text(currentBooking == null ? 'SALVA' : 'AGGIORNA'),
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    final String docId = umbrella.id;
                    final data = {
                      'umbrellaId': docId,
                      'clientName': nameController.text,
                      'startDate': Timestamp.fromDate(startDate),
                      'endDate': Timestamp.fromDate(endDate),
                      'notes': notesController.text,
                      'arrived': currentBooking?.arrived ?? false,
                    };
                    if (currentBooking != null) {
                      bookingsCollection.doc(currentBooking.id).update(data);
                    } else {
                      bookingsCollection.doc(docId).set(data);
                    }
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          );
        });
      },
    ).then((_) => setState(() => _isHighlightPending = false));
  }

  void _moveBooking(Umbrella newUmbrella) {
    if (_bookingToMove == null) return;
    final oldBookingId = _bookingToMove!.id;
    final newBookingId = newUmbrella.id;
    bookingsCollection.doc(oldBookingId).get().then((doc) {
      if (doc.exists) {
        final oldData = doc.data() as Map<String, dynamic>;
        final newData = {...oldData, 'umbrellaId': newBookingId};
        final batch = FirebaseFirestore.instance.batch();
        batch.set(bookingsCollection.doc(newBookingId), newData);
        batch.delete(bookingsCollection.doc(oldBookingId));
        return batch.commit();
      }
    }).then((_) {
      setState(() => _bookingToMove = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Prenotazione spostata all\'ombrellone ${newUmbrella.simpleId}')));
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante lo spostamento: $e')));
    });
  }

  void _showFreeUmbrellas(List<Booking> allBookings) {
    if (_filterDateRange == null) return;
    final allUmbrellas = widget.beachSectors.expand((s) => s.umbrellas).toList();
    final freeUmbrellas = allUmbrellas.where((u) => _findBookingFor(u, _filterDateRange, allBookings) == null).toList();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Ombrelloni liberi dal ${DateFormat('dd/MM/yy').format(_filterDateRange!.start)} al ${DateFormat('dd/MM/yy').format(_filterDateRange!.end)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: freeUmbrellas.isEmpty
                ? const Text('Nessun ombrellone libero nel periodo selezionato.')
                : ListView.builder(
              shrinkWrap: true,
              itemCount: freeUmbrellas.length,
              itemBuilder: (context, index) {
                final umbrella = freeUmbrellas[index];
                return ListTile(
                  title: Text('Ombrellone ${umbrella.simpleId} (Settore: ${umbrella.sectorName})'),
                  onTap: () { Navigator.of(context).pop(); _showBookingDialog(umbrella, null); },
                );
              },
            ),
          ),
          actions: [TextButton(child: const Text('CHIUDI'), onPressed: () => Navigator.of(context).pop())],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMoveMode = _bookingToMove != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isMoveMode ? 'Sposta Prenotazione' : 'Mappa Spiaggia'),
        actions: isMoveMode ? [] : [
          DropdownButton<String>(
            value: null,
            hint: const Text('Settore', style: TextStyle(color: Colors.black87)),
            onChanged: (String? newValue) { /* Logica filtro non implementata */ },
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('Tutti')),
              ...widget.beachSectors.map((s) => DropdownMenuItem<String>(value: s.name, child: Text(s.name))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (isMoveMode) Container(padding: const EdgeInsets.all(12), color: Colors.orange.shade200, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.move_down, size: 20), const SizedBox(width: 8), Flexible(child: Text('SPOSTA: Seleziona un ombrellone libero', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900), overflow: TextOverflow.ellipsis))])),
          if (_filterDateRange != null && !isMoveMode) Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.green.shade100, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('Periodo: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)), Text('${DateFormat('dd/MM/yyyy').format(_filterDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_filterDateRange!.end)}', style: TextStyle(color: Colors.green.shade900))])),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: bookingsCollection.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('Errore di connessione.'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final allBookings = snapshot.data!.docs.map((doc) => Booking.fromFirestore(doc)).toList();
                if (widget.highlightUmbrellaId != null && _isHighlightPending) {
                  try {
                    final umbrellaToHighlight = widget.beachSectors.expand((s) => s.umbrellas).firstWhere((u) => u.id == widget.highlightUmbrellaId);
                    final bookingToHighlight = _findBookingFor(umbrellaToHighlight, _filterDateRange ?? DateTimeRange(start: DateTime.now(), end: DateTime.now().add(const Duration(days: 1))), allBookings);
                    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showBookingDialog(umbrellaToHighlight, bookingToHighlight); });
                  } catch (e) {/* Ombrellone non trovato */}
                }
                final visibleSectors = widget.beachSectors;
                return InteractiveViewer(
                  minScale: 0.2, maxScale: 5.0,
                  child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: visibleSectors.map((sector) => _buildSector(sector, allBookings)).toList())),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isMoveMode
          ? FloatingActionButton(onPressed: () => setState(() => _bookingToMove = null), tooltip: 'Annulla Spostamento', backgroundColor: Colors.red, child: const Icon(Icons.close))
          : FloatingActionButton.extended(
        onPressed: () {
          if (_filterDateRange == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleziona un periodo di date prima di cercare i liberi!'))); return; }
          bookingsCollection.get().then((snapshot) {
            final allBookings = snapshot.docs.map((doc) => Booking.fromFirestore(doc)).toList();
            _showFreeUmbrellas(allBookings);
          });
        },
        label: const Text('Suggerisci'),
        icon: const Icon(Icons.lightbulb_outline),
      ),
    );
  }

  Widget _buildSector(BeachSector sector, List<Booking> allBookings) {
    final umbrellaMap = {for (var u in sector.umbrellas) u.index: u};
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (sector.name == 'Mare') Container(height: 50, margin: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: Colors.blue.shade100, border: Border.symmetric(horizontal: BorderSide(color: Colors.blue.shade300, width: 2))), child: const Center(child: Text('MARE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
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
    final color = isBooked ? Colors.red.shade400 : Colors.green.shade400;
    bool isMoveMode = _bookingToMove != null;
    return GestureDetector(
      onTap: () {
        if (isMoveMode) {
          if (!isBooked) _moveBooking(umbrella);
        } else {
          _showBookingDialog(umbrella, booking);
        }
      },
      child: Opacity(
        opacity: (isMoveMode && isBooked) ? 0.3 : 1.0,
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(umbrella.simpleId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)))),
        ),
      ),
    );
  }
}
