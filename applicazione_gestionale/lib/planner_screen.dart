import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'availability.dart';
import 'booking_form.dart';
import 'booking_repository.dart';
import 'booking_service.dart';
import 'help_screen.dart';
import 'models.dart';

/// Planner a calendario: una riga per ombrellone, una colonna per giorno.
///
/// - Le prenotazioni sono barre con il nome del cliente: rosse quelle che toccano
///   il periodo scelto, grigie quelle prima e dopo. Così si vede tutto il quadro.
/// - Tocco su una barra: si apre la prenotazione (modifica, sposta, elimina).
/// - Tocco su uno spazio vuoto: nuova prenotazione su quell'ombrellone da quel giorno.
/// - "Sposta": si tocca la riga dell'ombrellone di destinazione; le righe libere
///   per quelle date diventano verdi.
class PlannerScreen extends StatefulWidget {
  final List<BeachSector> beachSectors;

  /// Periodo da evidenziare (es. quello scelto sulla mappa). Se null: oggi.
  final DateTimeRange? highlightRange;

  const PlannerScreen({super.key, required this.beachSectors, this.highlightRange});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  static const double dayWidth = 46;
  static const double rowHeight = 48;
  static const double labelWidth = 58;
  static const double headerHeight = 46;
  static const double sectorHeight = 30;
  static const int daysShown = 28;
  static const int daysBeforeHighlight = 3;

  static final _shortFmt = DateFormat('dd/MM');
  static final _weekdayFmt = DateFormat('EEE', 'it');
  static final _monthFmt = DateFormat('MMM', 'it');

  late DateTimeRange _highlight;
  late DateTime _windowStart;
  String? _selectedSectorName;

  final _hBody = ScrollController();
  final _hHeader = ScrollController();

  /// Modalità "sposta" / "allunga altrove": si tocca la riga di destinazione.
  Booking? _moving;
  DateTimeRange? _movingRange;
  bool _isExtension = false;

  BookingRepository get _repo => BookingRepository.instance;
  BookingService get _service => BookingService.instance;
  bool get _inMode => _moving != null;

  @override
  void initState() {
    super.initState();
    final today = _repo.today;
    _highlight = widget.highlightRange == null
        ? DateTimeRange(start: today, end: today)
        : DateTimeRange(start: dayOnly(widget.highlightRange!.start), end: dayOnly(widget.highlightRange!.end));
    _windowStart = _addDays(_highlight.start, -daysBeforeHighlight);
    _hBody.addListener(() {
      if (_hHeader.hasClients && _hHeader.offset != _hBody.offset) _hHeader.jumpTo(_hBody.offset);
    });
  }

  @override
  void dispose() {
    _hBody.dispose();
    _hHeader.dispose();
    super.dispose();
  }

  static DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  DateTime get _windowEnd => _addDays(_windowStart, daysShown - 1);

  /// Giorni di calendario da [a] a [b] (0 se è lo stesso giorno), senza problemi di ora legale.
  static int _daysFrom(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _conflictText(BookingConflictException e) =>
      'Occupato dal ${_shortFmt.format(e.conflict.startDate)} al ${_shortFmt.format(e.conflict.endDate)} da ${e.conflict.clientName}';

  void _shiftWindow(int days) {
    setState(() => _windowStart = _addDays(_windowStart, days));
    if (_hBody.hasClients) _hBody.jumpTo(0);
  }

  void _goToday() {
    final today = _repo.today;
    setState(() {
      _highlight = DateTimeRange(start: today, end: today);
      _windowStart = _addDays(today, -daysBeforeHighlight);
    });
    if (_hBody.hasClients) _hBody.jumpTo(0);
  }

  Future<void> _pickDate() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _highlight,
      firstDate: _repo.windowStart,
      lastDate: DateTime(_repo.today.year + 2, 12, 31),
      helpText: 'Periodo da evidenziare',
      locale: const Locale('it', 'IT'),
    );
    if (picked == null) return;
    setState(() {
      _highlight = DateTimeRange(start: dayOnly(picked.start), end: dayOnly(picked.end));
      _windowStart = _addDays(_highlight.start, -daysBeforeHighlight);
    });
    if (_hBody.hasClients) _hBody.jumpTo(0);
  }

  // ---------- Azioni ----------

  Umbrella? _umbrellaById(String id) => widget.beachSectors.expand((s) => s.umbrellas).where((u) => u.id == id).firstOrNull;

  Future<void> _openBooking(Booking b, List<Booking> all) async {
    final umbrella = _umbrellaById(b.umbrellaId) ?? Umbrella(id: b.umbrellaId, sectorName: b.sectorName, index: -1);
    await _openForm(umbrella, b, all, b.range);
  }

  Future<void> _newBooking(Umbrella umbrella, DateTime day, List<Booking> all) async {
    // Proposta: dal giorno toccato fino al giorno prima della prossima prenotazione (al massimo una settimana).
    final next = umbrellaTimeline(umbrella.id, DateTimeRange(start: day, end: day), all).next;
    var end = _addDays(day, 6);
    if (next != null && !dayOnly(next.startDate).isAfter(end)) end = _addDays(dayOnly(next.startDate), -1);
    if (end.isBefore(day)) end = day;
    await _openForm(umbrella, null, all, DateTimeRange(start: day, end: end));
  }

  Future<void> _openForm(Umbrella umbrella, Booking? existing, List<Booking> all, DateTimeRange initial) async {
    final result = await showBookingForm(
      context,
      umbrella: umbrella,
      existing: existing,
      initialRange: initial,
      knownClients: knownClients(all),
      allBookings: all,
      firstDate: _repo.windowStart,
    );
    if (result == null || !mounted) return;
    switch (result.action) {
      case BookingFormAction.saved:
        _showMessage(existing == null ? 'Prenotazione salvata.' : 'Prenotazione aggiornata.');
      case BookingFormAction.deleted:
        await _deleteWithUndo(result.booking);
      case BookingFormAction.move:
        setState(() {
          _moving = result.booking;
          _movingRange = result.range;
          _isExtension = false;
        });
      case BookingFormAction.extendElsewhere:
        setState(() {
          _moving = result.booking;
          _movingRange = result.range;
          _isExtension = true;
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

  Future<void> _placeOn(Umbrella target) async {
    final b = _moving!;
    if (!_isExtension && target.id == b.umbrellaId) {
      _showMessage('${b.clientName} è già sull\'ombrellone ${target.simpleId}: scegline un altro.');
      return;
    }
    final range = _movingRange ?? b.range;
    try {
      if (_isExtension) {
        await _service.createExtension(b, target.id, range);
        _showMessage('Giorni extra di ${b.clientName} sull\'ombrellone ${target.simpleId}.');
      } else {
        await _service.move(b, target.id, range);
        _showMessage('${b.clientName} spostato sull\'ombrellone ${target.simpleId}.');
      }
      if (mounted) setState(() => _moving = null);
    } on BookingConflictException catch (e) {
      _showMessage(_conflictText(e));
    } on BookingValidationException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Errore: $e');
    }
  }

  /// In modalità sposta: true se l'ombrellone è libero per le date da piazzare.
  bool _fitsMoving(Umbrella u, List<Booking> all) {
    final b = _moving!;
    if (!_isExtension && u.id == b.umbrellaId) return false; // è già lì
    final range = _movingRange ?? b.range;
    final candidate = Booking(
      id: _isExtension ? '' : b.id,
      umbrellaId: u.id,
      clientName: b.clientName,
      startDate: range.start,
      endDate: range.end,
    );
    return findConflict(candidate, all) == null;
  }

  // ---------- Interfaccia ----------

  @override
  Widget build(BuildContext context) {
    final sectors = _selectedSectorName == null
        ? widget.beachSectors
        : widget.beachSectors.where((s) => s.name == _selectedSectorName).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_inMode ? (_isExtension ? 'Allunga altrove' : 'Sposta') : 'Planner'),
        actions: _inMode
            ? [IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 28), tooltip: 'Annulla', onPressed: () => setState(() => _moving = null))]
            : [
                DropdownButton<String?>(
                  value: _selectedSectorName,
                  hint: const Text('Settore', style: TextStyle(color: Colors.black87)),
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setState(() => _selectedSectorName = v),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tutti')),
                    ...widget.beachSectors.map((s) => DropdownMenuItem<String?>(value: s.name, child: Text(s.name))),
                  ],
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: ValueListenableBuilder<List<Booking>?>(
        valueListenable: _repo.bookings,
        builder: (context, bookings, _) {
          if (bookings == null) return const Center(child: CircularProgressIndicator());
          return Column(children: [
            if (_inMode) _modeBanner() else _periodBar(),
            if (!_inMode) _hint(),
            _header(),
            Expanded(
              child: SingleChildScrollView(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: labelWidth, child: Column(children: [for (final s in sectors) ..._labels(s, bookings)])),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _hBody,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: daysShown * dayWidth,
                        child: Column(children: [for (final s in sectors) ..._rows(s, bookings)]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _periodBar() {
    final color = Colors.green.shade900;
    return Container(
      color: Colors.green.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Settimana prima', onPressed: () => _shiftWindow(-7)),
        Expanded(
          child: InkWell(
            onTap: _pickDate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Dal ${_shortFmt.format(_windowStart)} al ${_shortFmt.format(_windowEnd)}',
                  textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ),
          ),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Settimana dopo', onPressed: () => _shiftWindow(7)),
        TextButton(onPressed: _goToday, child: const Text('OGGI')),
      ]),
    );
  }

  Widget _hint() {
    Widget swatch(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 12)),
        ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 4, children: [
        swatch(Colors.red.shade400, 'Nel periodo ${_shortFmt.format(_highlight.start)}${_highlight.start == _highlight.end ? '' : '-${_shortFmt.format(_highlight.end)}'}'),
        swatch(Colors.blueGrey.shade300, 'Prima e dopo'),
        const Text('Tocca uno spazio vuoto per prenotare', style: TextStyle(fontSize: 12, color: Colors.grey)),
        InkWell(
          onTap: () => HelpScreen.open(context, HelpTopic.planner),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.help_outline, size: 16, color: Colors.green.shade800),
            const SizedBox(width: 2),
            Text('Guida', style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }

  Widget _modeBanner() {
    final b = _moving!;
    final range = _movingRange ?? b.range;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: _isExtension ? Colors.blue.shade200 : Colors.orange.shade200,
      child: Column(children: [
        Text('${_isExtension ? 'ALLUNGA' : 'SPOSTA'}: ${b.clientName} · dal ${_shortFmt.format(range.start)} al ${_shortFmt.format(range.end)}',
            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        const Text('Tocca la riga di un ombrellone verde (libero per queste date)', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
      ]),
    );
  }

  Widget _header() {
    final today = _repo.today;
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(children: [
        const SizedBox(width: labelWidth, child: Center(child: Text('Ombr.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
        Expanded(
          child: SingleChildScrollView(
            controller: _hHeader,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(children: [
              for (var i = 0; i < daysShown; i++)
                Builder(builder: (_) {
                  final d = _addDays(_windowStart, i);
                  final isToday = d == today;
                  final inHighlight = !d.isBefore(_highlight.start) && !d.isAfter(_highlight.end);
                  return Container(
                    width: dayWidth,
                    decoration: BoxDecoration(
                      color: isToday ? Colors.green.shade700 : (inHighlight ? Colors.green.shade100 : null),
                      border: Border(left: BorderSide(color: Colors.grey.shade300, width: d.day == 1 ? 2 : 0.5)),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(d.day == 1 || i == 0 ? _monthFmt.format(d) : _weekdayFmt.format(d),
                          style: TextStyle(fontSize: 10, color: isToday ? Colors.white : Colors.grey.shade700)),
                      Text('${d.day}',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isToday ? Colors.white : Colors.black87)),
                    ]),
                  );
                }),
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _labels(BeachSector sector, List<Booking> all) => [
        Container(
          height: sectorHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 6),
          color: Colors.grey.shade200,
          child: Text(sector.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.clip, softWrap: false),
        ),
        for (final u in _orderedUmbrellas(sector))
          Container(
            height: rowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _inMode ? (_fitsMoving(u, all) ? Colors.green.shade200 : Colors.grey.shade100) : Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200), right: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Text(u.simpleId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
      ];

  List<Widget> _rows(BeachSector sector, List<Booking> all) => [
        Container(height: sectorHeight, color: Colors.grey.shade200),
        for (final u in _orderedUmbrellas(sector)) _row(u, all),
      ];

  /// Ombrelloni nell'ordine della mappa (per righe, da sinistra a destra).
  List<Umbrella> _orderedUmbrellas(BeachSector s) => s.umbrellas.toList()..sort((a, b) => a.index.compareTo(b.index));

  Widget _row(Umbrella u, List<Booking> all) {
    final rowBookings = all.where((b) => b.umbrellaId == u.id && !dayOnly(b.endDate).isBefore(_windowStart) && !dayOnly(b.startDate).isAfter(_windowEnd));
    final fits = _inMode && _fitsMoving(u, all);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        if (_inMode) {
          _placeOn(u);
          return;
        }
        final index = (details.localPosition.dx / dayWidth).floor().clamp(0, daysShown - 1);
        _newBooking(u, _addDays(_windowStart, index), all);
      },
      child: SizedBox(
        height: rowHeight,
        width: daysShown * dayWidth,
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                windowStart: _windowStart,
                days: daysShown,
                dayWidth: dayWidth,
                today: _repo.today,
                highlight: _highlight,
                tint: _inMode ? (fits ? Colors.green.shade50 : Colors.grey.shade100) : null,
              ),
            ),
          ),
          for (final b in rowBookings) _bar(b, all),
        ]),
      ),
    );
  }

  Widget _bar(Booking b, List<Booking> all) {
    final start = dayOnly(b.startDate).isBefore(_windowStart) ? _windowStart : dayOnly(b.startDate);
    final end = dayOnly(b.endDate).isAfter(_windowEnd) ? _windowEnd : dayOnly(b.endDate);
    final left = _daysFrom(_windowStart, start);
    final span = _daysFrom(start, end) + 1;
    final cutLeft = dayOnly(b.startDate).isBefore(_windowStart);
    final cutRight = dayOnly(b.endDate).isAfter(_windowEnd);
    final inHighlight = b.overlaps(_highlight);
    final isMoving = _moving?.id == b.id;
    final color = isMoving ? Colors.orange.shade400 : (inHighlight ? Colors.red.shade400 : Colors.blueGrey.shade300);

    return Positioned(
      left: left * dayWidth + 2,
      top: 5,
      width: span * dayWidth - 4,
      height: rowHeight - 10,
      child: GestureDetector(
        onTap: _inMode ? null : () => _openBooking(b, all),
        child: Semantics(
          button: true,
          label: '${b.clientName}, dal ${_shortFmt.format(b.startDate)} al ${_shortFmt.format(b.endDate)}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(cutLeft ? 0 : 8),
                right: Radius.circular(cutRight ? 0 : 8),
              ),
            ),
            child: Row(children: [
              if (cutLeft) const Icon(Icons.chevron_left, size: 14, color: Colors.white),
              if (b.arrived) const Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.check, size: 13, color: Colors.white)),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, height: 1.1)),
                  if (span >= 2)
                    Text('${_shortFmt.format(b.startDate)}-${_shortFmt.format(b.endDate)}',
                        maxLines: 1, overflow: TextOverflow.clip, softWrap: false,
                        style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.1)),
                ]),
              ),
              if (b.amountDue > 0) const Icon(Icons.euro, size: 13, color: Colors.white),
              if (cutRight) const Icon(Icons.chevron_right, size: 14, color: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Sfondo di una riga: righe dei giorni, fine settimana, periodo evidenziato, oggi.
class _GridPainter extends CustomPainter {
  final DateTime windowStart;
  final int days;
  final double dayWidth;
  final DateTime today;
  final DateTimeRange highlight;
  final Color? tint;

  _GridPainter({
    required this.windowStart,
    required this.days,
    required this.dayWidth,
    required this.today,
    required this.highlight,
    this.tint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tint != null) canvas.drawRect(Offset.zero & size, Paint()..color = tint!);
    final line = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 0.5;
    for (var i = 0; i < days; i++) {
      final d = DateTime(windowStart.year, windowStart.month, windowStart.day + i);
      final rect = Rect.fromLTWH(i * dayWidth, 0, dayWidth, size.height);
      final inHighlight = !d.isBefore(highlight.start) && !d.isAfter(highlight.end);
      if (inHighlight) {
        canvas.drawRect(rect, Paint()..color = Colors.green.shade50);
      } else if (d.weekday >= DateTime.saturday) {
        canvas.drawRect(rect, Paint()..color = Colors.grey.shade50);
      }
      if (d == today) {
        canvas.drawRect(Rect.fromLTWH(i * dayWidth + dayWidth / 2 - 1, 0, 2, size.height), Paint()..color = Colors.green.shade300);
      }
      canvas.drawLine(Offset(i * dayWidth, 0), Offset(i * dayWidth, size.height), line);
    }
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), Paint()..color = Colors.grey.shade200);
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.windowStart != windowStart || old.highlight != highlight || old.tint != tint || old.today != today;
}
