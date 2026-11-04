import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'availability.dart';
import 'booking_service.dart';
import 'contact.dart';
import 'models.dart';
import 'sector_style.dart';
import 'umbrella_timeline_view.dart';

enum BookingFormAction {
  /// Prenotazione salvata (nuova o modificata).
  saved,

  /// L'utente ha confermato l'eliminazione: la esegue chi ha aperto il form (per poter offrire "Annulla").
  deleted,

  /// Spostare la prenotazione: si sceglie il nuovo ombrellone sulla mappa.
  move,

  /// Aggiungere i giorni extra su un altro ombrellone.
  extendElsewhere,
}

class BookingFormResult {
  final BookingFormAction action;
  final Booking booking;

  /// move: nuovo periodo. extendElsewhere: giorni extra.
  final DateTimeRange? range;
  const BookingFormResult(this.action, this.booking, {this.range});
}

/// Apre la scheda di una prenotazione (nuova se [existing] è null).
Future<BookingFormResult?> showBookingForm(
  BuildContext context, {
  required Umbrella umbrella,
  Booking? existing,
  required DateTimeRange initialRange,
  Map<String, String> knownClients = const {},
  List<Booking> allBookings = const [],
  DateTime? firstDate,
  String? initialClientName,
}) {
  return showDialog<BookingFormResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BookingFormDialog(
      umbrella: umbrella,
      existing: existing,
      initialRange: initialRange,
      knownClients: knownClients,
      allBookings: allBookings,
      firstDate: firstDate,
      initialClientName: initialClientName,
    ),
  );
}

class BookingFormDialog extends StatefulWidget {
  final Umbrella umbrella;
  final Booking? existing;
  final DateTimeRange initialRange;
  final Map<String, String> knownClients;

  /// Prenotazioni della stagione, per mostrare chi c'è prima e dopo su questo ombrellone.
  final List<Booking> allBookings;
  final DateTime? firstDate;

  /// Nome già scritto (es. dal suggeritore) per una nuova prenotazione.
  final String? initialClientName;

  const BookingFormDialog({
    super.key,
    required this.umbrella,
    this.existing,
    required this.initialRange,
    this.knownClients = const {},
    this.allBookings = const [],
    this.firstDate,
    this.initialClientName,
  });

  @override
  State<BookingFormDialog> createState() => _BookingFormDialogState();
}

class _BookingFormDialogState extends State<BookingFormDialog> {
  static final _dateFmt = DateFormat('dd/MM/yyyy');
  static final _shortFmt = DateFormat('dd/MM');

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  late final TextEditingController _price;
  late final TextEditingController _deposit;
  final FocusNode _nameFocus = FocusNode();

  late DateTime _start;
  late DateTime _end;
  late bool _paid;
  String? _error;
  Booking? _conflict;
  bool _saving = false;

  Booking? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final b = _existing;
    final initialName = b?.clientName ?? widget.initialClientName?.trim() ?? '';
    _name = TextEditingController(text: initialName);
    // Cliente già visto: si ripropone il suo telefono.
    final knownPhone = widget.knownClients.entries.where((e) => e.key.toLowerCase() == initialName.toLowerCase()).firstOrNull?.value;
    _phone = TextEditingController(text: b?.phone ?? knownPhone ?? '');
    _notes = TextEditingController(text: b?.notes ?? '');
    _price = TextEditingController(text: b?.price == null ? '' : _amountText(b!.price!));
    _deposit = TextEditingController(text: (b?.deposit ?? 0) > 0 ? _amountText(b!.deposit) : '');
    _start = dayOnly(b?.startDate ?? widget.initialRange.start);
    _end = dayOnly(b?.endDate ?? widget.initialRange.end);
    _paid = b?.paid ?? false;
    _phone.addListener(_refresh);
    _price.addListener(_refresh);
    _deposit.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  static String _amountText(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _price.dispose();
    _deposit.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Prenotazione con i dati inseriti. null se un importo non è valido.
  Booking? _candidate() {
    final priceText = _price.text.trim();
    final depositText = _deposit.text.trim();
    final price = parseAmountInput(priceText);
    final deposit = parseAmountInput(depositText);
    if (priceText.isNotEmpty && price == null) {
      setState(() => _error = 'Prezzo non valido.');
      return null;
    }
    if (depositText.isNotEmpty && deposit == null) {
      setState(() => _error = 'Acconto non valido.');
      return null;
    }
    return Booking(
      id: _existing?.id ?? '',
      umbrellaId: widget.umbrella.id,
      clientName: _name.text,
      startDate: _start,
      endDate: _end,
      notes: _notes.text,
      arrived: _existing?.arrived ?? false,
      phone: _phone.text,
      price: price,
      deposit: deposit ?? 0,
      paid: _paid,
    );
  }

  Future<void> _save() async {
    final candidate = _candidate();
    if (candidate == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _conflict = null;
    });
    try {
      // Solo i campi cambiati rispetto a quando la scheda è stata aperta.
      await BookingService.instance.save(candidate, original: _existing);
      if (mounted) Navigator.of(context).pop(BookingFormResult(BookingFormAction.saved, candidate));
    } on BookingConflictException catch (e) {
      if (!mounted) return;
      setState(() {
        _conflict = e.conflict;
        _error = 'OCCUPATO: dal ${_shortFmt.format(e.conflict.startDate)} al ${_shortFmt.format(e.conflict.endDate)} da ${e.conflict.clientName}';
      });
    } on BookingValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Errore nel salvataggio: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final b = _existing!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminare la prenotazione?'),
        content: Text('${b.clientName}\nOmbrellone ${widget.umbrella.simpleId}, dal ${_shortFmt.format(b.startDate)} al ${_shortFmt.format(b.endDate)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ANNULLA')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('ELIMINA', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && mounted) Navigator.of(context).pop(BookingFormResult(BookingFormAction.deleted, b));
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final minDate = widget.firstDate ?? DateTime(DateTime.now().year, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: current.isBefore(minDate) ? current : minDate,
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      locale: const Locale('it', 'IT'),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = dayOnly(picked);
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = dayOnly(picked);
        if (_end.isBefore(_start)) _start = _end;
      }
      _error = null;
      _conflict = null;
    });
  }

  Widget _dateRow(String label, DateTime date, {required bool isStart}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        TextButton.icon(
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(_dateFmt.format(date), style: const TextStyle(fontSize: 16)),
          onPressed: () => _pickDate(isStart: isStart),
        ),
      ],
    );
  }

  Widget _nameField() {
    return RawAutocomplete<String>(
      textEditingController: _name,
      focusNode: _nameFocus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.length < 2) return const Iterable<String>.empty();
        return widget.knownClients.keys.where((n) => n.toLowerCase().contains(q) && n.toLowerCase() != q).take(8);
      },
      onSelected: (name) {
        final phone = widget.knownClients[name] ?? '';
        if (_phone.text.trim().isEmpty && phone.isNotEmpty) _phone.text = phone;
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nome Cliente', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 340),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(o),
                    subtitle: (widget.knownClients[o] ?? '').isNotEmpty ? Text(widget.knownClients[o]!) : null,
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existing = _existing;
    final days = daysBetween(_start, _end) + 1;
    final price = parseAmountInput(_price.text);
    final deposit = parseAmountInput(_deposit.text) ?? 0;
    final due = (!_paid && price != null && price - deposit > 0) ? price - deposit : 0.0;
    final canExtendElsewhere = _conflict != null && existing != null && _end.isAfter(dayOnly(existing.endDate));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ombrellone ${widget.umbrella.simpleId}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Center(child: SectorBadge(widget.umbrella.sectorName, text: 'Settore: ${widget.umbrella.sectorName}')),
              const SizedBox(height: 20),
              _nameField(),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Telefono (facoltativo)',
                  border: const OutlineInputBorder(),
                  suffixIcon: existing == null
                      ? null
                      : ContactButtons(
                          phone: _phone.text,
                          whatsappMessage: bookingSummaryMessage(existing.copyWith(clientName: _name.text.trim(), startDate: _start, endDate: _end)),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade100),
                ),
                child: Column(children: [
                  _dateRow('Dal:', _start, isStart: true),
                  const Divider(height: 1),
                  _dateRow('Al:', _end, isStart: false),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(days == 1 ? '1 giorno' : '$days giorni', style: TextStyle(color: Colors.green.shade900)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              NeighborsBox(
                timeline: umbrellaTimeline(widget.umbrella.id, DateTimeRange(start: _start, end: _end), widget.allBookings,
                    excludeId: existing?.id),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Prezzo €', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _deposit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Acconto €', border: OutlineInputBorder()),
                  ),
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Saldato'),
                subtitle: due > 0 ? Text('Da incassare: ${formatEuro(due)}', style: TextStyle(color: Colors.orange.shade900)) : null,
                value: _paid,
                onChanged: (v) => setState(() => _paid = v),
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              if ((existing?.updatedBy ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Ultima modifica: ${existing!.updatedBy}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_error!,
                        style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canExtendElsewhere)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                      onPressed: () {
                        final extraStart = addDays(existing.endDate, 1);
                        Navigator.of(context).pop(BookingFormResult(
                          BookingFormAction.extendElsewhere,
                          existing,
                          range: DateTimeRange(start: extraStart, end: _end),
                        ));
                      },
                      icon: const Icon(Icons.add_to_photos, color: Colors.white, size: 18),
                      label: const Text('ALLUNGA ALTROVE', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  if (existing != null)
                    IconButton(
                      onPressed: _saving ? null : _confirmDelete,
                      icon: const Icon(Icons.delete_forever, color: Colors.red, size: 28),
                      tooltip: 'ELIMINA',
                    ),
                  if (existing != null)
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () {
                              final edited = _candidate();
                              if (edited == null) return;
                              try {
                                BookingService.validate(edited);
                              } on BookingValidationException catch (e) {
                                setState(() => _error = e.message);
                                return;
                              }
                              Navigator.of(context).pop(BookingFormResult(
                                BookingFormAction.move,
                                edited,
                                range: DateTimeRange(start: _start, end: _end),
                              ));
                            },
                      icon: const Icon(Icons.move_up, color: Colors.orange, size: 28),
                      tooltip: 'SPOSTA SU ALTRO OMBRELLONE',
                    ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('ANNULLA', style: TextStyle(fontSize: 16)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(existing == null ? 'SALVA' : 'AGGIORNA',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
