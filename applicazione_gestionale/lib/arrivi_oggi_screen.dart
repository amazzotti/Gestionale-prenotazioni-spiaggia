import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';import 'package:intl/intl.dart';
import 'map_screen.dart'; // Importa la classe Booking (che usa 'arrived')

class ArriviOggiScreen extends StatefulWidget {
  const ArriviOggiScreen({super.key});

  @override
  State<ArriviOggiScreen> createState() => _ArriviOggiScreenState();
}

class _ArriviOggiScreenState extends State<ArriviOggiScreen> {
  DateTime get _startOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Aggiorna il campo 'arrived' in Firebase
  Future<void> _toggleArrived(String bookingId, bool currentStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({'arrived': !currentStatus});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'aggiornamento: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayTimestamp = Timestamp.fromDate(_startOfToday);
    final formattedDate = DateFormat('dd/MM/yyyy').format(_startOfToday);

    return Scaffold(
      appBar: AppBar(
        title: Text('Arrivi del $formattedDate'),
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Cerca le prenotazioni la cui data di inizio è oggi
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('startDate', isEqualTo: todayTimestamp)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Si è verificato un errore: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nessun arrivo previsto per oggi.'));
          }

          final arrivals = snapshot.data!.docs
              .map((doc) => Booking.fromFirestore(doc))
              .toList();

          arrivals.sort((a, b) => a.clientName.compareTo(b.clientName));

          return ListView.builder(
            itemCount: arrivals.length,
            itemBuilder: (context, index) {
              final booking = arrivals[index];

              String displayId = booking.umbrellaId;
              if (booking.umbrellaId.startsWith('Tende-')) {
                displayId = booking.umbrellaId.replaceFirst('Tende-', '');
              } else {
                displayId = booking.umbrellaId.split('-').last;
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: CheckboxListTile(
                  value: booking.arrived,
                  activeColor: Colors.green,
                  onChanged: (bool? value) {
                    if (value != null) {
                      _toggleArrived(booking.id, booking.arrived);
                    }
                  },
                  title: Text(
                    '${booking.clientName} - Ombrellone $displayId',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: booking.arrived
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: booking.arrived ? Colors.grey.shade600 : null,
                    ),
                  ),
                  subtitle: Text(
                      'Periodo: ${DateFormat('dd/MM').format(booking.startDate)} - ${DateFormat('dd/MM').format(booking.endDate)}\nSettore: ${booking.umbrellaId.split('-').first}'),
                  isThreeLine: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
