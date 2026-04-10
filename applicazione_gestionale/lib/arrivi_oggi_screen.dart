import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'map_screen.dart';

class ArriviOggiScreen extends StatefulWidget {
  const ArriviOggiScreen({super.key});

  @override
  State<ArriviOggiScreen> createState() => _ArriviOggiScreenState();
}

class _ArriviOggiScreenState extends State<ArriviOggiScreen> with SingleTickerProviderStateMixin {
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _toggleArrived(String bookingId, bool currentStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({'arrived': !currentStatus});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    }
  }

  Future<void> _deleteBooking(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma Cancellazione'),
        content: const Text('Sei sicuro di voler eliminare questa prenotazione?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULLA')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ELIMINA', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedSelectedDate = DateFormat('dd/MM/yyyy').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestione Arrivi'),
        backgroundColor: Colors.green,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          isScrollable: false, // Assicura che le tab occupino tutto lo spazio
          tabs: [
            const Tab(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.0),
                child: Text('ARRIVI OGGI', style: TextStyle(fontSize: 13), textAlign: TextAlign.center),
              ),
            ),
            Tab(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text('ARRIVI IN DATA\n($formattedSelectedDate)', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                locale: const Locale('it', 'IT'),
              );
              if (pickedDate != null) {
                setState(() => _selectedDate = pickedDate);
              }
            },
            tooltip: 'Seleziona Data',
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('bookings').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          final allBookings = snapshot.data!.docs.map((doc) => Booking.fromFirestore(doc)).toList();
          
          return TabBarView(
            controller: _tabController,
            children: [
              _buildList(allBookings, filterDate: DateTime.now(), onlyArrivals: true),
              _buildList(allBookings, filterDate: _selectedDate, onlyArrivals: false),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(List<Booking> bookings, {required DateTime filterDate, required bool onlyArrivals}) {
    final targetDate = DateTime(filterDate.year, filterDate.month, filterDate.day);

    final filtered = bookings.where((b) {
      final start = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
      final end = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);
      
      if (onlyArrivals) {
        return start.isAtSameMomentAs(targetDate);
      } else {
        return !targetDate.isBefore(start) && !targetDate.isAfter(end);
      }
    }).toList();

    filtered.sort((a, b) => a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase()));

    if (filtered.isEmpty) {
      return const Center(child: Text('Nessuna prenotazione trovata per questa data.'));
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final b = filtered[index];
        String num = b.umbrellaId.contains('-') ? b.umbrellaId.split('-').last : b.umbrellaId;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: Checkbox(
              value: b.arrived, 
              activeColor: Colors.green,
              onChanged: (_) => _toggleArrived(b.id, b.arrived)
            ),
            title: Text('${b.clientName} - Ombr. $num', 
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                decoration: b.arrived ? TextDecoration.lineThrough : null,
                color: b.arrived ? Colors.grey : null,
              )
            ),
            subtitle: Text('Dal ${DateFormat('dd/MM').format(b.startDate)} al ${DateFormat('dd/MM').format(b.endDate)}\nSettore: ${b.umbrellaId.split('-').first}'),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red), 
              onPressed: () => _deleteBooking(b.id)
            ),
          ),
        );
      },
    );
  }
}
