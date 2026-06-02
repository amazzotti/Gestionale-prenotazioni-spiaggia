import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// --- MODELLO DATI PRENOTAZIONE ---
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
    final data = doc.data() as Map<String, dynamic>;
    
    DateTime parseDate(dynamic d) {
      if (d == null) return DateTime(2000);
      if (d is Timestamp) return d.toDate();
      if (d is String) {
        DateTime? p = DateTime.tryParse(d);
        if (p != null) return p;
        try {
          final parts = d.split('/');
          if (parts.length == 3) return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } catch (_) {}
      }
      if (d is int) return DateTime.fromMillisecondsSinceEpoch(d);
      return DateTime(2000);
    }

    return Booking(
      id: doc.id,
      umbrellaId: (data['umbrellaId'] ?? data['id'] ?? doc.id).toString(),
      clientName: (data['clientName'] ?? data['nome'] ?? data['cliente'] ?? data['name'] ?? 'Senza Nome').toString(),
      startDate: parseDate(data['startDate'] ?? data['start_date'] ?? data['dataInizio'] ?? data['data_inizio']),
      endDate: parseDate(data['endDate'] ?? data['end_date'] ?? data['dataFine'] ?? data['data_fine']),
      notes: (data['notes'] ?? data['note'] ?? '').toString(),
      arrived: data['arrived'] == true || data['arrivato'] == true,
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

// --- SCHERMATA DELLA MAPPA ---
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
  String? _selectedSectorName;

  // Stato per l'allungamento in un secondo ombrellone (Split)
  DateTimeRange? _extraDaysRange;
  String? _extraDaysClientName;
  String? _extraDaysNotes;

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

  void _showBookingDialog(Umbrella umbrella, Booking? currentBooking, List<Booking> allBookings) {
    final nameController = TextEditingController(text: currentBooking?.clientName);
    final notesController = TextEditingController(text: currentBooking?.notes);
    DateTime startDate = currentBooking?.startDate ?? _filterDateRange?.start ?? DateTime.now();
    DateTime endDate = currentBooking?.endDate ?? _filterDateRange?.end ?? startDate;
    String? overlapError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: StatefulBuilder(builder: (context, setDialogState) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(20),
                width: MediaQuery.of(context).size.width * 0.9,
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ombrellone ${umbrella.simpleId}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Settore: ${umbrella.sectorName}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome Cliente',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade100),
                      ),
                      child: Column(
                        children: [
                          _buildDateRow('Dal:', startDate, (date) {
                            setDialogState(() {
                              startDate = date;
                              if (endDate.isBefore(startDate)) endDate = startDate;
                              overlapError = null;
                            });
                          }),
                          const Divider(),
                          _buildDateRow('Al:', endDate, (date) {
                            setDialogState(() {
                              endDate = date;
                              overlapError = null;
                            });
                          }),
                        ],
                      ),
                    ),
                    if (overlapError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            overlapError!,
                            style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (overlapError != null && currentBooking != null && endDate.isAfter(currentBooking.endDate))
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                            onPressed: () {
                              final originalEnd = currentBooking.endDate;
                              final extraStart = originalEnd.add(const Duration(days: 1));
                              final extraRange = DateTimeRange(
                                start: DateTime(extraStart.year, extraStart.month, extraStart.day),
                                end: DateTime(endDate.year, endDate.month, endDate.day),
                              );
                              
                              Navigator.of(context).pop();
                              setState(() {
                                _extraDaysRange = extraRange;
                                _extraDaysClientName = nameController.text;
                                _extraDaysNotes = notesController.text;
                                _filterDateRange = extraRange; // Filtro mappa per i giorni extra
                              });
                            },
                            icon: const Icon(Icons.add_to_photos, color: Colors.white, size: 18),
                            label: const Text('ALLUNGA ALTROVE', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        if (currentBooking != null)
                          IconButton(
                            onPressed: () {
                              bookingsCollection.doc(currentBooking.id).delete();
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.delete_forever, color: Colors.red, size: 28),
                            tooltip: 'ELIMINA',
                          ),
                        if (currentBooking != null)
                          IconButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              setState(() {
                                // Sincronizzo: sposta con le date allungate inserite nel dialog
                                _filterDateRange = DateTimeRange(start: startDate, end: endDate);
                                _bookingToMove = currentBooking;
                              });
                            },
                            icon: const Icon(Icons.move_up, color: Colors.orange, size: 28),
                            tooltip: 'SPOSTA TUTTO',
                          ),
                        TextButton(
                          child: const Text('ANNULLA', style: TextStyle(fontSize: 16)),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: Text(currentBooking == null ? 'SALVA' : 'AGGIORNA', 
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            if (nameController.text.isNotEmpty) {
                              // Controllo sovrapposizioni
                              Booking? conflict;
                              final s1 = DateTime(startDate.year, startDate.month, startDate.day);
                              final e1 = DateTime(endDate.year, endDate.month, endDate.day);

                              for (var b in allBookings) {
                                if (b.umbrellaId == umbrella.id && b.id != currentBooking?.id) {
                                  final s2 = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
                                  final e2 = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);
                                  
                                  if (!(e1.isBefore(s2) || s1.isAfter(e2))) {
                                    conflict = b;
                                    break;
                                  }
                                }
                              }

                              if (conflict != null) {
                                setDialogState(() {
                                  overlapError = 'OCCUPATO: dal ${DateFormat('dd/MM').format(conflict!.startDate)} al ${DateFormat('dd/MM').format(conflict!.endDate)} da ${conflict!.clientName}';
                                });
                                return;
                              }

                              final data = {
                                'umbrellaId': umbrella.id,
                                'clientName': nameController.text,
                                'startDate': Timestamp.fromDate(startDate),
                                'endDate': Timestamp.fromDate(endDate),
                                'notes': notesController.text,
                                'arrived': currentBooking?.arrived ?? false,
                              };
                              if (currentBooking != null) {
                                bookingsCollection.doc(currentBooking.id).update(data);
                              } else {
                                bookingsCollection.add(data);
                              }
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    ).then((_) => setState(() => _isHighlightPending = false));
  }

  Widget _buildDateRow(String label, DateTime date, Function(DateTime) onSelected) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        TextButton.icon(
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 16)),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              locale: const Locale('it', 'IT'),
            );
            if (picked != null) onSelected(picked);
          },
        ),
      ],
    );
  }

  void _moveBooking(Umbrella newUmbrella) {
    if (_bookingToMove == null) return;
    // Uso le date del filtro (sincronizzate nel dialog)
    final newStart = _filterDateRange?.start ?? _bookingToMove!.startDate;
    final newEnd = _filterDateRange?.end ?? _bookingToMove!.endDate;

    bookingsCollection.doc(_bookingToMove!.id).update({
      'umbrellaId': newUmbrella.id,
      'startDate': Timestamp.fromDate(newStart),
      'endDate': Timestamp.fromDate(newEnd),
    }).then((_) {
      if (mounted) {
        setState(() => _bookingToMove = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Prenotazione spostata all\'ombrellone ${newUmbrella.simpleId}')));
      }
    });
  }

  void _createExtraBooking(Umbrella umbrella) {
    if (_extraDaysRange == null) return;
    bookingsCollection.add({
      'umbrellaId': umbrella.id,
      'clientName': _extraDaysClientName,
      'startDate': Timestamp.fromDate(_extraDaysRange!.start),
      'endDate': Timestamp.fromDate(_extraDaysRange!.end),
      'notes': _extraDaysNotes ?? '',
      'arrived': false,
    }).then((_) {
      if (mounted) {
        setState(() {
          _extraDaysRange = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Allungamento creato sull\'ombrellone ${umbrella.simpleId}')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isMoveMode = _bookingToMove != null;
    bool isExtraMode = _extraDaysRange != null;
    final visibleSectors = _selectedSectorName == null
        ? widget.beachSectors
        : widget.beachSectors.where((s) => s.name == _selectedSectorName).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(isMoveMode ? 'Sposta Prenotazione' : (isExtraMode ? 'Allunga su altro Ombrellone' : 'Mappa Spiaggia')),
        actions: (isMoveMode || isExtraMode) 
          ? [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 28),
                tooltip: 'Annulla',
                onPressed: () => setState(() { _bookingToMove = null; _extraDaysRange = null; }),
              ),
              const SizedBox(width: 8),
            ]
          : [
          DropdownButton<String>(
            value: _selectedSectorName,
            hint: const Text('Settore', style: TextStyle(color: Colors.black87)),
            onChanged: (String? newValue) {
              setState(() {
                _selectedSectorName = newValue;
              });
            },
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
          if (isMoveMode) 
            Container(
              padding: const EdgeInsets.all(12), 
              color: Colors.orange.shade200, 
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center, 
                    children: [
                      const Icon(Icons.move_down, size: 20, color: Color(0xFF5D4037)), 
                      const SizedBox(width: 8), 
                      Flexible(
                        child: Text(
                          'SPOSTA: ${_bookingToMove!.clientName}', 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D4037)), 
                          overflow: TextOverflow.ellipsis
                        )
                      )
                    ]
                  ),
                  Text(
                    'Periodo: ${DateFormat('dd/MM').format(_filterDateRange!.start)} - ${DateFormat('dd/MM').format(_filterDateRange!.end)}',
                    style: const TextStyle(color: Color(0xFF5D4037), fontSize: 13, fontWeight: FontWeight.bold),
                  )
                ],
              )
            ),
          if (isExtraMode) 
            Container(
              padding: const EdgeInsets.all(12), 
              color: Colors.blue.shade200, 
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center, 
                    children: [
                      const Icon(Icons.add_chart, size: 20, color: Colors.blueGrey), 
                      const SizedBox(width: 8), 
                      Flexible(
                        child: Text(
                          'ALLUNGA: Seleziona dove aggiungere i giorni extra', 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey), 
                          overflow: TextOverflow.ellipsis
                        )
                      )
                    ]
                  ),
                  Text(
                    'Periodo Extra: ${DateFormat('dd/MM').format(_extraDaysRange!.start)} - ${DateFormat('dd/MM').format(_extraDaysRange!.end)}',
                    style: const TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.bold),
                  )
                ],
              )
            ),
          if (_filterDateRange != null && !isMoveMode && !isExtraMode) 
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
              color: Colors.green.shade100, 
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  Text('Periodo: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)), 
                  Text('${DateFormat('dd/MM/yyyy').format(_filterDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_filterDateRange!.end)}', style: TextStyle(color: Colors.green.shade900))
                ]
              )
            ),
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
                    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showBookingDialog(umbrellaToHighlight, bookingToHighlight, allBookings); });
                  } catch (e) {}
                }

                return InteractiveViewer(
                  minScale: 0.2, maxScale: 5.0,
                  child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: visibleSectors.map((sector) => _buildSector(sector, allBookings)).toList())),
                );
              },
            ),
          ),
        ],
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
            if (umbrella == null) return Container(decoration: BoxDecoration(color: Colors.grey.shade200.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)));
            final booking = _findBookingFor(umbrella, _filterDateRange, allBookings);
            return _buildUmbrella(umbrella, booking, allBookings);
          },
        ),
      ]),
    );
  }

  Widget _buildUmbrella(Umbrella umbrella, Booking? booking, List<Booking> allBookings) {
    final isBooked = booking != null;
    final color = isBooked ? Colors.red.shade400 : Colors.green.shade400;
    bool isMoveMode = _bookingToMove != null;
    bool isExtraMode = _extraDaysRange != null;
    return GestureDetector(
      onTap: () {
        if (isExtraMode) {
          if (!isBooked) _createExtraBooking(umbrella);
        } else if (isMoveMode) {
          if (!isBooked) _moveBooking(umbrella);
        } else {
          _showBookingDialog(umbrella, booking, allBookings);
        }
      },
      child: Opacity(
        opacity: ((isMoveMode || isExtraMode) && isBooked) ? 0.3 : 1.0,
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(umbrella.simpleId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)))),
        ),
      ),
    );
  }
}
