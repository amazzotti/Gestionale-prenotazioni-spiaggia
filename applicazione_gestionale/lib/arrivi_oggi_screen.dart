import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ArriviOggiScreen extends StatefulWidget {
  const ArriviOggiScreen({super.key});

  @override
  State<ArriviOggiScreen> createState() => _ArriviOggiScreenState();
}

class _ArriviOggiScreenState extends State<ArriviOggiScreen> {
  List<Map<String, dynamic>> _arrivi = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchArriviOggi();
  }

  Future<void> _fetchArriviOggi() async {
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);

      final querySnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('startDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('startDate', isLessThan: Timestamp.fromDate(startOfTomorrow))
          .get();

      if (mounted) {
        setState(() {
          _arrivi = querySnapshot.docs.map((doc) {
            return {'id': doc.id, ...doc.data()};
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Errore nel caricamento degli arrivi.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arrivi di Oggi'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_arrivi.isEmpty) {
      return const Center(child: Text('Nessun arrivo previsto per oggi.'));
    }

    return ListView.builder(
      itemCount: _arrivi.length,
      itemBuilder: (context, index) {
        final booking = _arrivi[index];
        final bookingId = booking['id'];
        final nome = booking['clientName'] ?? 'Nome non disponibile';
        final notes = booking['notes'] as String? ?? '';
        final arrived = booking['arrived'] ?? false;

        return CheckboxListTile(
          title: Text(nome),
          subtitle: notes.isNotEmpty ? Text(notes) : null,
          value: arrived,
          onChanged: (bool? value) {
            if (value != null) {
              // Update in Firestore
              FirebaseFirestore.instance
                  .collection('bookings')
                  .doc(bookingId)
                  .update({'arrived': value});
              
              // Update local state and rebuild UI
              setState(() {
                _arrivi[index]['arrived'] = value;
              });
            }
          },
        );
      },
    );
  }
}
