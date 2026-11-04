import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'availability.dart';
import 'booking_repository.dart';
import 'layout_repository.dart';
import 'models.dart';

class EditorUmbrella {
  String? id;
  bool isActive;
  final int index;

  EditorUmbrella({this.id, this.isActive = false, required this.index});

  // Metodo helper per estrarre solo il numero (es. '51' da 'Mare-51')
  // o l'identificativo della tenda (es. 'T1-1' da 'Tende-T1-1')
  String get simpleId {
    if (id == null) return '';
    if (id!.startsWith('Tende-')) {
      return id!.replaceFirst('Tende-', '');
    }
    return id!.split('-').last;
  }
}

class BeachEditorScreen extends StatefulWidget {
  const BeachEditorScreen({super.key});

  @override
  State<BeachEditorScreen> createState() => _BeachEditorScreenState();
}

class _BeachEditorScreenState extends State<BeachEditorScreen> {
  final List<String> _sectors = ['Mare', 'Tende', 'Dietro'];
  String? _selectedSector;
  bool _isLoading = false;

  List<EditorUmbrella> _gridState = [];
  List<int> _walkwayColumns = [];
  int _crossAxisCount = 10;
  int _rowCount = 10;
  final _rowsController = TextEditingController();
  final _colsController = TextEditingController();

  /// Ombrelloni presenti quando il settore è stato aperto (per controllare il salvataggio).
  Set<String> _loadedIds = {};

  FirebaseFirestore get _db => LayoutRepository.instance.db;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Applica righe e colonne scritte nei campi (tasto ✓ o Invio).
  /// Ogni ombrellone resta nella sua riga e colonna; quelli con prenotazioni non si possono togliere.
  Future<void> _applyDimensions() async {
    final rows = int.tryParse(_rowsController.text.trim());
    final cols = int.tryParse(_colsController.text.trim());
    if (rows == null || cols == null || rows <= 0 || cols <= 0 || rows > 50 || cols > 50) {
      _message('Righe e colonne devono essere numeri da 1 a 50.');
      _rowsController.text = '$_rowCount';
      _colsController.text = '$_crossAxisCount';
      return;
    }
    if (rows == _rowCount && cols == _crossAxisCount) return;

    final active = {for (final u in _gridState) if (u.isActive && u.id != null) u.index: u.id!};
    final result = resizeLayout(active, oldCols: _crossAxisCount, newRows: rows, newCols: cols);
    if (result.dropped.isNotEmpty) {
      if (BookingRepository.instance.bookings.value == null) {
        _message('Prenotazioni in caricamento, riprova tra un attimo.');
        return;
      }
      final withBookings = result.dropped.where((id) => _bookingsCount(id) > 0).map(umbrellaLabelFromId).toList();
      if (withBookings.isNotEmpty) {
        _message('Non si può: gli ombrelloni ${withBookings.join(', ')} hanno prenotazioni e uscirebbero dalla griglia.');
        _rowsController.text = '$_rowCount';
        _colsController.text = '$_crossAxisCount';
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Togliere degli ombrelloni?'),
          content: Text('Con $rows righe e $cols colonne questi ombrelloni escono dalla griglia: '
              '${result.dropped.map(umbrellaLabelFromId).join(', ')}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ANNULLA')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('TOGLI')),
          ],
        ),
      );
      if (ok != true) {
        _rowsController.text = '$_rowCount';
        _colsController.text = '$_crossAxisCount';
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _gridState = List.generate(rows * cols, (i) => EditorUmbrella(index: i));
      result.kept.forEach((index, id) => _gridState[index] = EditorUmbrella(id: id, isActive: true, index: index));
      _walkwayColumns = _walkwayColumns.where((c) => c < cols).toList();
      _rowCount = rows;
      _crossAxisCount = cols;
    });
  }

  Future<void> _loadLayoutForSector(String sector) async {
    setState(() {
      _isLoading = true;
      _selectedSector = sector;
      _gridState = [];
    });

    try {
      final doc = await _db.collection('beachLayout').doc(sector).get();
      int rows = 10;
      int cols = 10;
      List<EditorUmbrella> newGrid;

      if (doc.exists) {
        final data = doc.data()!;
        cols = data['crossAxisCount'] ?? 10;
        rows = data['rows'] ?? 10;
        _walkwayColumns = List<int>.from(data['walkwayColumns'] ?? []);
        final umbrellas = data['umbrellas'] as List<dynamic>;

        newGrid = List.generate(rows * cols, (i) => EditorUmbrella(index: i));
        for (var u in umbrellas) {
          final index = u['index'];
          if (index != null && index < newGrid.length) {
            // Ricostruiamo l'ID univoco partendo da quello semplice salvato
            final sectorName = data['name'];
            final simpleId = u['id']; // Es. '51' o 'T1-1'
            final uniqueId = '$sectorName-$simpleId'; // Es. 'Mare-51' o 'Tende-T1-1'
            newGrid[index] = EditorUmbrella(id: uniqueId, isActive: true, index: index);
          }
        }
      } else {
        _walkwayColumns = [];
        switch (sector) {
          case 'Mare': rows = 5; cols = 9; break;
          case 'Tende': rows = 2; cols = 11; break;
          case 'Dietro': rows = 10; cols = 10; break;
        }
        newGrid = List.generate(rows * cols, (i) => EditorUmbrella(index: i));
      }

      if (mounted) {
        setState(() {
          _rowsController.text = rows.toString();
          _colsController.text = cols.toString();
          _crossAxisCount = cols;
          _rowCount = rows;
          _gridState = newGrid;
          _loadedIds = {for (final u in newGrid) if (u.isActive && u.id != null) u.id!};
        });
      }
    } catch (e) {
      debugPrint("Errore caricamento layout: $e");
      if (mounted) setState(() => _gridState = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Prenotazioni (stagione in corso) collegate a un ombrellone.
  int _bookingsCount(String umbrellaId) =>
      (BookingRepository.instance.bookings.value ?? const <Booking>[]).where((b) => b.umbrellaId == umbrellaId).length;

  /// true se l'ombrellone si può togliere; altrimenti avvisa e restituisce false.
  bool _canRemove(EditorUmbrella umbrella) {
    final id = umbrella.id;
    if (id == null) return true;
    if (BookingRepository.instance.bookings.value == null) {
      _message('Prenotazioni in caricamento, riprova tra un attimo.');
      return false;
    }
    final count = _bookingsCount(id);
    if (count == 0) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('L\'ombrellone ${umbrella.simpleId} ha $count prenotazion${count == 1 ? 'e' : 'i'}: '
          'spostale o eliminale prima di toglierlo dalla mappa.'),
    ));
    return false;
  }

  void _onUmbrellaTap(int index) {
    if (_selectedSector == null) return;
    final umbrella = _gridState[index];

    if (umbrella.isActive) {
      if (!_canRemove(umbrella)) return;
      setState(() {
        umbrella.isActive = false;
        umbrella.id = null;
      });
      return;
    }

    final String newId;
    if (_selectedSector == 'Tende') {
      // Le tende si numerano per fila: T1-1, T1-2... T2-1...
      final row = index ~/ _crossAxisCount;
      final prefix = 'T${row + 1}';
      final used = _gridState
          .where((u) => u.isActive && u.id != null && u.id!.split('-').length == 3 && u.id!.split('-')[1] == prefix)
          .map((u) => int.tryParse(u.id!.split('-').last) ?? 0)
          .toSet();
      newId = 'Tende-$prefix-${nextUmbrellaNumber(used)}';
    } else {
      final sectorPrefix = _selectedSector!;
      final used = _gridState
          .where((u) => u.isActive && u.id != null && u.id!.startsWith('$sectorPrefix-'))
          .map((u) => int.tryParse(u.simpleId) ?? 0)
          .toSet();
      newId = '$sectorPrefix-${nextUmbrellaNumber(used)}';
    }

    setState(() {
      umbrella.id = newId;
      umbrella.isActive = true;
    });
  }

  Future<void> _saveLayout() async {
    if (_selectedSector == null) return;
    final activeIds = {for (final u in _gridState) if (u.isActive && u.id != null) u.id!};
    final removedWithBookings = _loadedIds.difference(activeIds).where((id) => _bookingsCount(id) > 0).map(umbrellaLabelFromId).toList();
    if (removedWithBookings.isNotEmpty) {
      _message('Non salvo: gli ombrelloni ${removedWithBookings.join(', ')} hanno prenotazioni. Spostale prima.');
      return;
    }
    setState(() => _isLoading = true);

    try {
      final activeUmbrellas = _gridState
          .where((u) => u.isActive && u.id != null)
          .map((u) {
        // Salviamo un ID SEMPLICE nel database.
        String idToSave = _selectedSector == 'Tende'
            ? u.id!.replaceFirst('Tende-', '') // da 'Tende-T1-1' a 'T1-1'
            : u.simpleId; // da 'Mare-51' a '51'
        return {'id': idToSave, 'index': u.index};
      })
          .toList();

      await _db.collection('beachLayout').doc(_selectedSector!).set({
        'name': _selectedSector,
        'rows': _rowCount,
        'crossAxisCount': _crossAxisCount,
        'umbrellas': activeUmbrellas,
        'walkwayColumns': _walkwayColumns,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Layout per il settore $_selectedSector salvato!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il salvataggio: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleWalkway(int index) {
    final col = index % _crossAxisCount;
    if (_walkwayColumns.contains(col)) {
      setState(() => _walkwayColumns.remove(col));
      return;
    }
    // La passerella toglie gli ombrelloni della colonna: si blocca se qualcuno ha prenotazioni.
    final inColumn = [for (var i = 0; i < _gridState.length; i++) if (i % _crossAxisCount == col) _gridState[i]];
    for (final u in inColumn) {
      if (u.isActive && !_canRemove(u)) return;
    }
    setState(() {
      _walkwayColumns.add(col);
      for (final u in inColumn) {
        u.isActive = false;
        u.id = null;
      }
    });
  }

  Future<void> _deleteAllLayouts() async {
    setState(() => _isLoading = true);
    try {
      // Cancellazione a blocchi: un solo batch Firestore accetta al massimo 500 operazioni.
      final layoutSnapshot = await _db.collection('beachLayout').get();
      await BookingRepository.instance.deleteInChunks(layoutSnapshot.docs.map((d) => d.reference).toList());
      await BookingRepository.instance.deleteAllBookings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tutti i layout della mappa e le prenotazioni sono stati cancellati.')),
        );
        setState(() {
          _selectedSector = null;
          _gridState = [];
          _rowsController.clear();
          _colsController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante la cancellazione: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showDeleteMapConfirmationDialog() async {
    final confirmController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Cancellare la Mappa?'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Questa azione cancellerà TUTTI i settori della mappa e TUTTE le prenotazioni in modo irreversibile.\n\n'
                'Per confermare scrivi RESET qui sotto.'),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setDialogState(() {}),
              decoration: const InputDecoration(labelText: 'Scrivi RESET', border: OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('ANNULLA')),
            TextButton(
              onPressed: confirmController.text.trim().toUpperCase() == 'RESET' ? () => Navigator.of(dialogContext).pop(true) : null,
              child: const Text('CANCELLA TUTTO', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    confirmController.dispose();
    if (ok == true) await _deleteAllLayouts();
  }

  @override
  void dispose() {
    _rowsController.dispose();
    _colsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor Mappa Spiaggia'),
        actions: [
          if (_selectedSector != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveLayout,
              tooltip: 'Salva Layout Settore',
            ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed: _showDeleteMapConfirmationDialog,
            tooltip: 'Cancella Tutta la Mappa',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedSector,
                  hint: const Text('Settore'),
                  items: _sectors.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (value) {
                    if (value != null && value != _selectedSector) {
                      _loadLayoutForSector(value);
                    }
                  },
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _rowsController,
                  decoration: const InputDecoration(labelText: 'Righe', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _applyDimensions(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _colsController,
                  decoration: const InputDecoration(labelText: 'Colonne', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _applyDimensions(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.check_circle, size: 30),
                color: Colors.green.shade700,
                tooltip: 'Applica righe e colonne',
                onPressed: _selectedSector == null ? null : _applyDimensions,
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Text('Tap: Aggiungi/Rimuovi ombrellone. Tap Lungo: Imposta/Rimuovi passerella. Righe e colonne: scrivi i numeri e premi ✓.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const Divider(),
          if (_selectedSector == null)
            const Expanded(child: Center(child: Text('Seleziona un settore per iniziare')))
          else if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _crossAxisCount > 0 ? _crossAxisCount : 1,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _gridState.length,
                  itemBuilder: (context, index) {
                    final col = index % _crossAxisCount;
                    final isWalkway = _walkwayColumns.contains(col);
                    final umbrella = _gridState[index];
                    return GestureDetector(
                      onTap: () {
                        if (!isWalkway) _onUmbrellaTap(index);
                      },
                      onLongPress: () => _toggleWalkway(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isWalkway ? Colors.brown.shade200 : (umbrella.isActive ? Colors.blue.shade700 : Colors.grey.shade300),
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: isWalkway
                              ? const Icon(Icons.square_foot_rounded, size: 20, color: Colors.black54)
                              : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              umbrella.simpleId,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
