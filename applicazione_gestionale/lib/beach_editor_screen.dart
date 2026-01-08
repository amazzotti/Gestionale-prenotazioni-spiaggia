import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditorUmbrella {
  // Questo ID conterrà l'ID univoco, es. 'Mare-50'
  String? id;
  bool isActive;
  final int index;

  EditorUmbrella({this.id, this.isActive = false, required this.index});

  // Metodo helper per mostrare solo il numero nell'interfaccia
  String get simpleId {
    if (id == null) return '';
    // Estrae l'ultima parte dopo il trattino, es. '50' da 'Mare-50'
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
  final _rowsController = TextEditingController();
  final _colsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _colsController.addListener(_updateGridDimensions);
    _rowsController.addListener(_updateGridDimensions);
  }

  void _updateGridDimensions() {
    final cols = int.tryParse(_colsController.text) ?? 1;
    final rows = int.tryParse(_rowsController.text) ?? 1;
    if (cols <= 0 || rows <= 0) return;

    if (cols != _crossAxisCount || (rows * cols) != _gridState.length) {
      setState(() {
        _crossAxisCount = cols;
        final newGrid = List.generate(rows * cols, (i) => EditorUmbrella(index: i));
        for (final oldUmbrella in _gridState) {
          if (oldUmbrella.isActive && oldUmbrella.index < newGrid.length) {
            newGrid[oldUmbrella.index] = oldUmbrella;
          }
        }
        _gridState = newGrid;
      });
    }
  }

  Future<void> _loadLayoutForSector(String sector) async {
    setState(() {
      _isLoading = true;
      _selectedSector = sector;
      _gridState = []; // Pulisce la griglia
    });

    try {
      final doc = await FirebaseFirestore.instance.collection('beachLayout').doc(sector).get();

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
            // L'ID che carichiamo è già quello univoco
            newGrid[index] = EditorUmbrella(id: u['id'], isActive: true, index: index);
          }
        }
      } else {
        // Logica di default se il settore non esiste
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
          _gridState = newGrid;
        });
      }
    } catch (e) {
      print("Errore caricamento layout: $e");
      if (mounted) setState(() => _gridState = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onUmbrellaTap(int index) {
    if (_selectedSector == null) return; // Sicurezza
    final umbrella = _gridState[index];

    setState(() {
      if (umbrella.isActive) {
        // Disattiva l'ombrellone e cancella eventuali prenotazioni future
        if (umbrella.id != null) {
          FirebaseFirestore.instance.collection('bookings').doc(umbrella.id!).delete();
        }
        umbrella.isActive = false;
        umbrella.id = null;
      } else {
        // --- LOGICA CORRETTA PER CREARE UN ID UNIVOCO ---
        final sectorPrefix = _selectedSector!; // Es. 'Mare', 'Tende', 'Dietro'

        // Filtra gli ombrelloni ATTIVI solo in QUESTO settore
        final activeInSector = _gridState.where((u) => u.isActive && u.id != null && u.id!.startsWith(sectorPrefix));

        // Trova il numero più alto tra gli ID di questo settore
        final maxId = activeInSector
            .map((u) => int.tryParse(u.simpleId) ?? 0) // Usa simpleId per prendere solo il numero
            .fold(0, (max, current) => current > max ? current : max);

        // Crea il nuovo ID univoco
        final newId = '$sectorPrefix-${maxId + 1}'; // Es. 'Mare-51'

        umbrella.id = newId;
        umbrella.isActive = true;
      }
    });
  }

  void _toggleWalkway(int index) {
    final col = index % _crossAxisCount;
    setState(() {
      if (_walkwayColumns.contains(col)) {
        _walkwayColumns.remove(col);
      } else {
        _walkwayColumns.add(col);
        // Rimuove tutti gli ombrelloni nella colonna e le relative prenotazioni
        for (int i = 0; i < _gridState.length; i++) {
          if (i % _crossAxisCount == col) {
            final umbrella = _gridState[i];
            if (umbrella.isActive && umbrella.id != null) {
              FirebaseFirestore.instance.collection('bookings').doc(umbrella.id!).delete();
            }
            umbrella.isActive = false;
            umbrella.id = null;
          }
        }
      }
    });
  }

  Future<void> _saveLayout() async {
    if (_selectedSector == null) return;
    setState(() => _isLoading = true);

    try {
      // Salva gli ombrelloni con il loro ID univoco (es. 'Mare-50')
      final activeUmbrellas = _gridState
          .where((u) => u.isActive && u.id != null)
          .map((u) => {'id': u.id, 'index': u.index}) // L'ID è già univoco
          .toList();

      await FirebaseFirestore.instance.collection('beachLayout').doc(_selectedSector!).set({
        'name': _selectedSector,
        'rows': int.tryParse(_rowsController.text) ?? 10,
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

  Future<void> _deleteAllLayouts() async {
    setState(() => _isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();

      final beachLayoutCollection = FirebaseFirestore.instance.collection('beachLayout');
      final layoutSnapshot = await beachLayoutCollection.get();
      for (final doc in layoutSnapshot.docs) {
        batch.delete(doc.reference);
      }

      final bookingsCollection = FirebaseFirestore.instance.collection('bookings');
      final bookingsSnapshot = await bookingsCollection.get();
      for (final doc in bookingsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

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

  void _showDeleteMapConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancellare la Mappa?'),
        content: const Text("Questa azione cancellerà TUTTI i settori della mappa e TUTTE le prenotazioni in modo irreversibile. Sei sicuro?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ANNULLA')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Chiudi il dialogo
              _deleteAllLayouts(); // Esegui la cancellazione
            },
            child: const Text('CANCELLA TUTTO', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _rowsController.removeListener(_updateGridDimensions);
    _colsController.removeListener(_updateGridDimensions);
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
                  value: _selectedSector,
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
              Expanded(child: TextField(controller: _rowsController, decoration: const InputDecoration(labelText: 'Righe', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _colsController, decoration: const InputDecoration(labelText: 'Colonne', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Text('Tap: Aggiungi/Rimuovi ombrellone. Tap Lungo: Imposta/Rimuovi passerella.', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                              // Mostra solo il numero semplice
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
