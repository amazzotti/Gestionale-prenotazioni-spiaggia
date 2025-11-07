import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditorUmbrella {
  String? id;
  bool isActive;
  final int index;

  EditorUmbrella({this.id, this.isActive = false, required this.index});
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
      _gridState = []; // Pulisce la griglia per evitare di mostrare quella vecchia
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
            newGrid[index] = EditorUmbrella(id: u['id'], isActive: true, index: index);
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
    final umbrella = _gridState[index];

    setState(() {
        if (umbrella.isActive) {
            if (umbrella.id != null) {
                FirebaseFirestore.instance.collection('bookings').doc(umbrella.id!).delete();
            }
            umbrella.isActive = false;
            umbrella.id = null;
        } else {
            String newId;
            if (_selectedSector == 'Tende') {
                final row = index ~/ _crossAxisCount;
                final prefix = row == 0 ? 'T1' : 'T2';
                final activeInRow = _gridState.where((u) => u.isActive && u.id != null && u.id!.startsWith(prefix));
                final maxId = activeInRow
                    .map((u) => int.tryParse(u.id!.split('-').last) ?? 0)
                    .fold(0, (max, current) => current > max ? current : max);
                newId = '$prefix-${maxId + 1}';
            } else {
                final activeUmbrellas = _gridState.where((u) => u.isActive && u.id != null);
                final maxId = activeUmbrellas
                    .map((u) => int.tryParse(u.id!) ?? 0)
                    .fold(0, (max, current) => current > max ? current : max);
                newId = (maxId + 1).toString();
            }
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

    final activeUmbrellas = _gridState
        .where((u) => u.isActive && u.id != null)
        .map((u) => {'id': u.id, 'index': u.index})
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
  }

  Future<void> _deleteAllLayouts() async {
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
  }

  void _showDeleteMapConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancellare la Mappa?'),
        content: const Text("Sei sicuro di voler cancellare l'intero layout della spiaggia? L'azione è irreversibile e rimuoverà tutti i settori e le prenotazioni."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ANNULLA')),
          TextButton(
            onPressed: () async {
              await _deleteAllLayouts();
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mappa della spiaggia cancellata.')),
                );
                setState(() {
                  _selectedSector = null;
                  _gridState = [];
                });
              }
            },
            child: const Text('CANCELLA', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor Spiaggia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _showDeleteMapConfirmationDialog,
            tooltip: 'Cancella Mappa',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveLayout,
            tooltip: 'Salva Layout',
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
            child: Text('Tap: Aggiungi/Rimuovi. Tap Lungo: Passerella.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const Divider(),
          if (_selectedSector == null)
            const Expanded(child: Center(child: Text('Seleziona un settore per iniziare')))
          else if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
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
                            : FittedBox( // --- Ecco la soluzione per il testo!
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  umbrella.id ?? '',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
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

  @override
  void dispose() {
    _rowsController.dispose();
    _colsController.dispose();
    super.dispose();
  }
}
