import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'map_screen.dart'; // Import per la classe Booking

class ArriviOggiScreen extends StatefulWidget {
  const ArriviOggiScreen({super.key});

  @override
  State<ArriviOggiScreen> createState() => _ArriviOggiScreenState();
}

class _ArriviOggiScreenState extends State<ArriviOggiScreen> {
  List<Booking> _arrivi = [];
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
      final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final querySnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('startDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfToday))
          .get();
      
      final todayBookings = querySnapshot.docs.where((doc) {
          final booking = Booking.fromFirestore(doc);
          return booking.startDate.isBefore(endOfToday) && booking.endDate.isAfter(startOfToday.subtract(const Duration(seconds: 1)));
      }).map((doc) => Booking.fromFirestore(doc)).toList();

      if (mounted) {
        setState(() {
          _arrivi = todayBookings;
          _isLoading = false;
        });
      }
    } catch (e) {
      print(e);
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
        title: const Text('Arrivi e Presenze di Oggi'),
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
      return const Center(child: Text('Nessun arrivo o presenza per oggi.'));
    }

    return ListView.builder(
      itemCount: _arrivi.length,
      itemBuilder: (context, index) {
        final booking = _arrivi[index];

        return CheckboxListTile(
          title: Text('${booking.clientName} - Ombrellone ${booking.umbrellaId}'),
          subtitle: booking.notes.isNotEmpty ? Text(booking.notes) : null,
          value: booking.arrived,
          onChanged: (bool? value) {
            if (value != null) {
              FirebaseFirestore.instance
                  .collection('bookings')
                  .doc(booking.id)
                  .update({'arrived': value});
              
              setState(() {
                // Aggiorna l'oggetto locale per un feedback immediato
                _arrivi[index] = Booking(
                  id: booking.id,
                  umbrellaId: booking.umbrellaId,
                  clientName: booking.clientName,
                  startDate: booking.startDate,
                  endDate: booking.endDate,
                  notes: booking.notes,
                  arrived: value,
                );
              });
            }
          },
        );
      },
    );
  }
}
