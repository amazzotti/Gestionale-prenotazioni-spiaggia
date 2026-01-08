import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'map_screen.dart'; // Import per la classe Booking corretta

class ArriviOggiScreen extends StatefulWidget {
  const ArriviOggiScreen({super.key});

  @override
  State<ArriviOggiScreen> createState() => _ArriviOggiScreenState();
}

class _ArriviOggiScreenState extends State<ArriviOggiScreen> {

  // Funzione per ottenere la data di oggi a mezzanotte (per un confronto preciso)
  DateTime get _startOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Funzione per aggiornare lo stato del check-in su Firebase
  Future<void> _toggleCheckIn(String bookingId, bool currentStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({'isCheckedIn': !currentStatus}); // <-- USA IL CAMPO CORRETTO
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
    // Convertiamo la data di oggi in Timestamp per la query su Firestore
    final todayTimestamp = Timestamp.fromDate(_startOfToday);
    final formattedDate = DateFormat('dd/MM/yyyy').format(_startOfToday);

    return Scaffold(
      appBar: AppBar(
        title: Text('Arrivi del $formattedDate'),
        backgroundColor: Colors.green,
      ),
      // --- Usiamo uno StreamBuilder per aggiornamenti in tempo reale ---
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Questa query è specifica per gli "arrivi" del giorno.
        // Cerca tutte le prenotazioni che iniziano esattamente oggi.
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
          // CORREZIONE: Aggiunto .data! prima di .docs
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nessun arrivo previsto per oggi.'));
          }

          // Convertiamo i documenti in oggetti Booking
          final arrivals = snapshot.data!.docs
              .map((doc) => Booking.fromFirestore(doc))
              .toList();


          // Ordiniamo gli arrivi per nome del cliente
          arrivals.sort((a, b) => a.clientName.compareTo(b.clientName));

          return ListView.builder(
            itemCount: arrivals.length,
            itemBuilder: (context, index) {
              final booking = arrivals[index];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: CheckboxListTile(
                  // --- Usa il campo corretto 'isCheckedIn' ---
                  value: booking.isCheckedIn,
                  activeColor: Colors.green,
                  onChanged: (bool? value) {
                    if (value != null) {
                      _toggleCheckIn(booking.id, booking.isCheckedIn);
                    }
                  },
                  title: Text(
                    // Mostra il nome del cliente e l'ID semplice dell'ombrellone
                    '${booking.clientName} (Ombrellone: ${booking.umbrellaId.split('-').last})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      // Applica uno stile visivo per gli arrivi già registrati
                      decoration: booking.isCheckedIn
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: booking.isCheckedIn ? Colors.grey.shade600 : null,
                    ),
                  ),
                  subtitle: Text(
                      'Periodo: ${DateFormat('dd/MM').format(booking.startDate)} - ${DateFormat('dd/MM').format(booking.endDate)}\nSettore: ${booking.umbrellaId.split('-').first}'
                  ),
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
