import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'availability.dart';
import 'booking_form.dart';
import 'booking_repository.dart';
import 'booking_service.dart';
import 'models.dart';
import 'help_screen.dart';
import 'planner_screen.dart';
import 'sector_guard.dart';
import 'sector_style.dart';
import 'suggestions_sheet.dart';
import 'umbrella_timeline_view.dart';

export 'models.dart';

/// Colori della mappa (usati anche nella legenda).
class MapColors {
  static final free = Colors.green.shade500;
  static final full = Colors.red.shade500;
  static final walkway = Colors.brown.shade200;
  static final empty = Colors.grey.shade200.withValues(alpha: 0.5);
}

// --- SCHERMATA DELLA MAPPA ---
class MapScreen extends StatefulWidget {
  final String? highlightUmbrellaId;
  final DateTimeRange? filterDateRange;
  final List<BeachSector> beachSectors;

  /// Apre subito "Dove la metto?" (usato da "Nuova prenotazione").
  final bool openSuggestions;

  /// Settore da mostrare all'apertura (null = tutti). Le prenotazioni si fanno settore per settore.
  final String? initialSector;

  const MapScreen({
    super.key,
    this.highlightUmbrellaId,
    this.filterDateRange,
    required this.beachSectors,
    this.openSuggestions = false,
    this.initialSector,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static final _shortFmt = DateFormat('dd/MM');
  static final _dayFmt = DateFormat('EEE dd/MM/yyyy', 'it');

  late DateTimeRange _range;
  String? _selectedSectorName;
  bool _highlightPending = true;

  /// Modalità "sposta": si tocca un ombrellone libero per spostarci la prenotazione.
  Booking? _bookingToMove;
  DateTimeRange? _moveRange;

  /// Com'era la prenotazione prima delle modifiche nella scheda (per salvare solo i cambiamenti).
  Booking? _moveOriginal;

  /// Modalità "allunga altrove": si tocca un ombrellone libero per i giorni extra.
  Booking? _extendOriginal;
  DateTimeRange? _extraDaysRange;

  BookingRepository get _repo => BookingRepository.instance;
  BookingService get _service => BookingService.instance;

  bool get _isMoveMode => _bookingToMove != null;
  bool get _isExtraMode => _extraDaysRange != null;
  bool get _isSingleDay => dayOnly(_range.start) == dayOnly(_range.end);

  @override
  void initState() {
    super.initState();
    final today = _repo.today;
    _range = widget.filterDateRange ?? DateTimeRange(start: today, end: today);
    _selectedSectorName = widget.initialSector;
  }

  /// Periodo mostrato: in modalità sposta/allunga è quello della prenotazione da piazzare.
  DateTimeRange get _effectiveRange => _moveRange ?? _extraDaysRange ?? _range;

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _conflictText(BookingConflictException e) =>
      'Occupato dal ${_shortFmt.format(e.conflict.startDate)} al ${_shortFmt.format(e.conflict.endDate)} da ${e.conflict.clientName}';

  // ---------- Periodo ----------

  void _shiftDay(int delta) {
    final d = dayOnly(_range.start);
    final next = DateTime(d.year, d.month, d.day + delta);
    setState(() => _range = DateTimeRange(start: next, end: next));
  }

  void _goToday() {
    final today = _repo.today;
    setState(() => _range = DateTimeRange(start: today, end: today));
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: _range.start.isBefore(_repo.windowStart) ? _range.start : _repo.windowStart,
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Scegli il periodo da vedere',
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) setState(() => _range = DateTimeRange(start: dayOnly(picked.start), end: dayOnly(picked.end)));
  }

  // ---------- Suggerimenti ----------

  bool _suggestionsShown = false;

  void _openSuggestions() {
    final all = _repo.bookings.value;
    if (all == null) return;
    showSuggestionsSheet(
      context,
      range: _range,
      sectors: widget.beachSectors,
      bookings: all,
      initialSector: _selectedSectorName,
      onChoose: (umbrella, clientName) => _openForm(umbrella, null, all, initialRange: _range, initialClientName: clientName),
    );
  }

  // ---------- Azioni sulle prenotazioni ----------

  Future<void> _openForm(Umbrella umbrella, Booking? existing, List<Booking> all,
      {DateTimeRange? initialRange, String? initialClientName}) async {
    final result = await showBookingForm(
      context,
      umbrella: umbrella,
      existing: existing,
      initialRange: initialRange ?? _range,
      knownClients: knownClients(all),
      allBookings: all,
      firstDate: _repo.windowStart,
      initialClientName: initialClientName,
    );
    if (result == null || !mounted) return;
    switch (result.action) {
      case BookingFormAction.saved:
        _showMessage(existing == null ? 'Prenotazione salvata.' : 'Prenotazione aggiornata.');
      case BookingFormAction.deleted:
        await _deleteWithUndo(result.booking);
      case BookingFormAction.move:
        setState(() {
          _bookingToMove = result.booking;
          _moveOriginal = existing;
          _moveRange = result.range;
        });
      case BookingFormAction.extendElsewhere:
        setState(() {
          _extendOriginal = result.booking;
          _extraDaysRange = result.range;
        });
    }
  }

  Future<void> _deleteWithUndo(Booking b) async {
    try {
      await _service.delete(b);
    } catch (e) {
      _showMessage('Errore durante l\'eliminazione: $e');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text('Prenotazione di ${b.clientName} eliminata.'),
      action: SnackBarAction(
        label: 'ANNULLA',
        onPressed: () async {
          try {
            await _service.restore(b);
            _showMessage('Prenotazione ripristinata.');
          } on BookingConflictException catch (e) {
            _showMessage('Impossibile ripristinare. ${_conflictText(e)}');
          } catch (e) {
            _showMessage('Impossibile ripristinare: $e');
          }
        },
      ),
    ));
  }

  Future<void> _moveBookingTo(Umbrella target) async {
    final booking = _bookingToMove!;
    final range = _moveRange ?? booking.range;
    if (!await confirmSectorChange(context, booking, target)) return;
    try {
      await _service.move(booking, target.id, range, original: _moveOriginal);
      if (!mounted) return;
      setState(() {
        _moveOriginal = null;
        _bookingToMove = null;
        _moveRange = null;
      });
      _showMessage('Prenotazione spostata sull\'ombrellone ${target.simpleId}.');
    } on BookingConflictException catch (e) {
      _showMessage(_conflictText(e));
    } on BookingValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Errore: $e');
    }
  }

  Future<void> _createExtensionOn(Umbrella target) async {
    if (!await confirmSectorChange(context, _extendOriginal!, target, extension: true)) return;
    try {
      await _service.createExtension(_extendOriginal!, target.id, _extraDaysRange!);
      if (!mounted) return;
      setState(() {
        _extendOriginal = null;
        _extraDaysRange = null;
      });
      _showMessage('Giorni extra aggiunti sull\'ombrellone ${target.simpleId}.');
    } on BookingConflictException catch (e) {
      _showMessage(_conflictText(e));
    } catch (e) {
      _showMessage('Errore: $e');
    }
  }

  void _cancelModes() => setState(() {
        _bookingToMove = null;
        _moveRange = null;
        _extendOriginal = null;
        _extraDaysRange = null;
      });

  // ---------- Interfaccia ----------

  @override
  Widget build(BuildContext context) {
    final visibleSectors = _selectedSectorName == null
        ? widget.beachSectors
        : widget.beachSectors.where((s) => s.name == _selectedSectorName).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isMoveMode ? 'Sposta Prenotazione' : (_isExtraMode ? 'Allunga su altro Ombrellone' : 'Mappa Spiaggia')),
        actions: (_isMoveMode || _isExtraMode)
            ? [
                IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 28), tooltip: 'Annulla', onPressed: _cancelModes),
                const SizedBox(width: 8),
              ]
            : [
                IconButton(
                  icon: Icon(Icons.lightbulb_outline, color: Colors.amber.shade800),
                  tooltip: 'Dove la metto? (suggerimenti)',
                  onPressed: _openSuggestions,
                ),
                IconButton(
                  icon: const Icon(Icons.date_range),
                  tooltip: 'Planner',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => PlannerScreen(beachSectors: widget.beachSectors, highlightRange: _range, initialSector: _selectedSectorName)),
                  ),
                ),
                const SizedBox(width: 4),
              ],
      ),
      body: Column(
        children: [
          if (_isMoveMode) _modeBanner(Colors.orange.shade200, Icons.move_down, 'SPOSTA: ${_bookingToMove!.clientName}', 'Tocca un ombrellone verde'),
          if (_isExtraMode) _modeBanner(Colors.blue.shade200, Icons.add_chart, 'ALLUNGA: ${_extendOriginal!.clientName}', 'Tocca un ombrellone verde per i giorni extra'),
          if (!_isMoveMode && !_isExtraMode) _periodBar(),
          if (!_isMoveMode && !_isExtraMode)
            ValueListenableBuilder<List<Booking>?>(
              valueListenable: _repo.bookings,
              builder: (context, bookings, _) => SectorBar(
                sectors: widget.beachSectors,
                selected: _selectedSectorName,
                range: _range,
                bookings: bookings ?? const [],
                onSelected: (v) => setState(() => _selectedSectorName = v),
              ),
            ),
          _legend(),
          Expanded(
            child: ValueListenableBuilder<List<Booking>?>(
              valueListenable: _repo.bookings,
              builder: (context, bookings, _) {
                if (bookings == null) {
                  return ValueListenableBuilder<Object?>(
                    valueListenable: _repo.error,
                    builder: (context, error, _) => error != null
                        ? const Center(child: Text('Errore di connessione.'))
                        : const Center(child: CircularProgressIndicator()),
                  );
                }
                _openHighlightIfNeeded(bookings);
                if (widget.openSuggestions && !_suggestionsShown) {
                  _suggestionsShown = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _openSuggestions();
                  });
                }
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: visibleSectors.map((s) => _buildSector(s, bookings)).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Arrivando dalla ricerca, apre subito la prenotazione cercata.
  void _openHighlightIfNeeded(List<Booking> bookings) {
    if (!_highlightPending || widget.highlightUmbrellaId == null) return;
    _highlightPending = false;
    final umbrella = widget.beachSectors.expand((s) => s.umbrellas).where((u) => u.id == widget.highlightUmbrellaId).firstOrNull;
    if (umbrella == null) return;
    final booking = bookingsInRange(umbrella.id, _range, bookings).firstOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openForm(umbrella, booking, bookings);
    });
  }

  Widget _modeBanner(Color color, IconData icon, String title, String subtitle) {
    final r = _effectiveRange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: color,
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
        ]),
        Text('Periodo: ${_shortFmt.format(r.start)} - ${_shortFmt.format(r.end)} · $subtitle', style: const TextStyle(fontSize: 13)),
      ]),
    );
  }

  Widget _periodBar() {
    final color = Colors.green.shade900;
    return Container(
      color: Colors.green.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(children: [
        if (_isSingleDay) IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Giorno prima', onPressed: () => _shiftDay(-1)),
        Expanded(
          child: InkWell(
            onTap: _pickRange,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _isSingleDay
                    ? _dayFmt.format(_range.start)
                    : 'Dal ${_shortFmt.format(_range.start)} al ${_shortFmt.format(_range.end)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
              ),
            ),
          ),
        ),
        if (_isSingleDay) IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Giorno dopo', onPressed: () => _shiftDay(1)),
        TextButton(onPressed: _goToday, child: const Text('OGGI')),
      ]),
    );
  }

  Widget _legend() {
    Widget item(Color c, String label, {IconData? icon}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
            child: icon == null ? null : Icon(icon, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(spacing: 12, runSpacing: 4, alignment: WrapAlignment.center, children: [
        item(MapColors.free, 'Libero'),
        item(MapColors.full, 'Occupato'),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _badge(Icons.euro, Colors.orange.shade900),
          const SizedBox(width: 4),
          const Text('Da incassare', style: TextStyle(fontSize: 12)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _badge(Icons.check, Colors.green.shade800),
          const SizedBox(width: 4),
          const Text('Arrivato', style: TextStyle(fontSize: 12)),
        ]),
        InkWell(
          onTap: () => HelpScreen.open(context, HelpTopic.mappa),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.help_outline, size: 16, color: Colors.green.shade800),
            const SizedBox(width: 2),
            Text('Guida', style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSector(BeachSector sector, List<Booking> allBookings) {
    final umbrellaMap = {for (final u in sector.umbrellas) u.index: u};
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (sector.name == 'Mare')
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              border: Border.symmetric(horizontal: BorderSide(color: Colors.blue.shade300, width: 2)),
            ),
            child: const Center(child: Text('MARE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
          ),
        Text(sector.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: sector.crossAxisCount, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: sector.rows * sector.crossAxisCount,
          itemBuilder: (context, index) {
            final col = index % sector.crossAxisCount;
            if (sector.walkwayColumns.contains(col)) {
              return Container(
                decoration: BoxDecoration(color: MapColors.walkway, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.square_foot_rounded, size: 20, color: Colors.black54),
              );
            }
            final umbrella = umbrellaMap[index];
            if (umbrella == null) {
              return Container(decoration: BoxDecoration(color: MapColors.empty, borderRadius: BorderRadius.circular(8)));
            }
            return _buildUmbrella(umbrella, allBookings);
          },
        ),
      ]),
    );
  }

  Widget _buildUmbrella(Umbrella umbrella, List<Booking> allBookings) {
    final range = _effectiveRange;
    final inRange = bookingsInRange(umbrella.id, range, allBookings);
    final isBooked = inRange.isNotEmpty;
    final color = isBooked ? MapColors.full : MapColors.free;
    final inMode = _isMoveMode || _isExtraMode;
    final hasDue = inRange.any((b) => b.amountDue > 0);
    final arrived = _isSingleDay && inRange.isNotEmpty && inRange.every((b) => b.arrived);

    // Anteprima sul quadrato: periodo della prenotazione (o quante sono).
    // Su due righe ("07/07" sopra "19/07") perché sul telefono i quadrati sono piccoli.
    final List<String> preview;
    if (inRange.length == 1) {
      final b = inRange.first;
      preview = [_shortFmt.format(b.startDate), _shortFmt.format(b.endDate)];
    } else if (inRange.length > 1) {
      preview = ['${inRange.length}', 'pren.'];
    } else {
      preview = const [];
    }

    return Semantics(
      button: true,
      label: 'Ombrellone ${umbrella.simpleId}, ${isBooked ? 'occupato' : 'libero'}',
      child: GestureDetector(
        onTap: () {
          if (_isExtraMode) {
            if (!isBooked) _createExtensionOn(umbrella);
          } else if (_isMoveMode) {
            if (!isBooked) _moveBookingTo(umbrella);
          } else if (inRange.length > 1) {
            _showUmbrellaBookings(umbrella, allBookings);
          } else {
            _openForm(umbrella, inRange.firstOrNull, allBookings);
          }
        },
        onLongPress: inMode ? null : () => _showUmbrellaBookings(umbrella, allBookings),
        child: Opacity(
          opacity: (inMode && isBooked) ? 0.3 : 1.0,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(umbrella.simpleId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1.1)),
                      for (final line in preview)
                        Text(line, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, height: 1.05)),
                    ]),
                  ),
                ),
              ),
            ),
            // Bollini sull'angolo, fuori dal testo: € = da incassare, ✓ = arrivato.
            if (hasDue) Positioned(top: -5, right: -5, child: _badge(Icons.euro, Colors.orange.shade900)),
            if (arrived) Positioned(top: -5, left: -5, child: _badge(Icons.check, Colors.green.shade800)),
          ]),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, Color color) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1),
        ),
        child: Icon(icon, size: 10, color: color),
      );

  /// Quadro dell'ombrellone: chi c'era PRIMA, chi c'è NEL PERIODO, chi arriva DOPO, più tutta la stagione.
  /// Si apre con pressione lunga, o con un tocco se nel periodo ci sono più prenotazioni.
  void _showUmbrellaBookings(Umbrella umbrella, List<Booking> allBookings) {
    final range = _range;
    final timeline = umbrellaTimeline(umbrella.id, range, allBookings);
    final season = allBookings.where((b) => b.umbrellaId == umbrella.id).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final freeStretch = firstFreeStretch(timeline.inPeriod, range);
    void open(Booking b, BuildContext sheetContext) {
      Navigator.pop(sheetContext);
      _openForm(umbrella, b, allBookings);
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Ombrellone ${umbrella.simpleId} · ${umbrella.sectorName}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    UmbrellaTimelineView(timeline: timeline, onOpen: (b) => open(b, sheetContext)),
                    if (season.length > timeline.inPeriod.length + (timeline.previous == null ? 0 : 1) + (timeline.next == null ? 0 : 1))
                      ExpansionTile(
                        title: Text('Tutta la stagione (${season.length} prenotazioni)'),
                        children: [
                          for (final b in season)
                            ListTile(
                              dense: true,
                              title: Text(b.clientName),
                              subtitle: Text('dal ${_shortFmt.format(b.startDate)} al ${_shortFmt.format(b.endDate)}'),
                              trailing: const Icon(Icons.edit, size: 18),
                              onTap: () => open(b, sheetContext),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(freeStretch == null
                      ? 'NUOVA PRENOTAZIONE'
                      : 'NUOVA PRENOTAZIONE DAL ${_shortFmt.format(freeStretch.start)} AL ${_shortFmt.format(freeStretch.end)}'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openForm(umbrella, null, allBookings, initialRange: freeStretch);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
