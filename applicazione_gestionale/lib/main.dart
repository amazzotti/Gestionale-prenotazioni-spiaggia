import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'arrivi_oggi_screen.dart';
import 'beach_editor_screen.dart';
import 'map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class StripedBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintGreen = Paint()..color = Colors.green.withValues(alpha: 0.1);
    final paintWhite = Paint()..color = Colors.white.withValues(alpha: 0.1);
    const stripeWidth = 30.0;
    for (double i = 0; i < size.width; i += stripeWidth * 2) {
      canvas.drawRect(Rect.fromLTWH(i, 0, stripeWidth, size.height), paintGreen);
      canvas.drawRect(Rect.fromLTWH(i + stripeWidth, 0, stripeWidth, size.height), paintWhite);
    }
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestionale Spiaggia B. Carla 98',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('it', 'IT'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<BeachSector> _beachSectors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBeachConfiguration();
  }

  Future<void> _loadBeachConfiguration() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance.collection('beachLayout').get();
      if (snapshot.docs.isNotEmpty) {
        final sectors = snapshot.docs.map((doc) {
          final data = doc.data();
          final sectorName = data['name'] as String;
          final umbrellasData = (data['umbrellas'] as List<dynamic>);
          final umbrellas = umbrellasData.map((u) {
            final simpleId = u['id'];
            final uniqueId = '$sectorName-$simpleId';
            return Umbrella(id: uniqueId, sectorName: sectorName, index: u['index']);
          }).toList();
          return BeachSector(
            name: sectorName,
            rows: data['rows'],
            crossAxisCount: data['crossAxisCount'],
            umbrellas: umbrellas,
            walkwayColumns: List<int>.from(data['walkwayColumns'] ?? []),
          );
        }).toList();
        final sectorOrder = {'Mare': 1, 'Tende': 2, 'Dietro': 3};
        sectors.sort((a, b) {
          final orderA = sectorOrder[a.name] ?? 99;
          final orderB = sectorOrder[b.name] ?? 99;
          return orderA.compareTo(orderB);
        });
        if (mounted) setState(() => _beachSectors = sectors);
      } else {
        if (mounted) setState(() => _beachSectors = []);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore caricamento mappa: $e')));
        setState(() => _beachSectors = []);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSearch(BuildContext context) async {
    if (_isLoading || _beachSectors.isEmpty) return;
    final snapshot = await FirebaseFirestore.instance.collection('bookings').get();
    final allBookings = snapshot.docs.map((doc) => Booking.fromFirestore(doc)).toList();
    if (!context.mounted) return;
    final selectedBooking = await showSearch<Booking?>(context: context, delegate: BookingSearchDelegate(allBookings));
    if (selectedBooking != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapScreen(
            highlightUmbrellaId: selectedBooking.umbrellaId,
            filterDateRange: DateTimeRange(start: selectedBooking.startDate, end: selectedBooking.endDate),
            beachSectors: _beachSectors,
          ),
        ),
      );
    }
  }

  void _showResetDialog(BuildContext context) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resettare la Stagione?'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Questa azione cancellerà TUTTE le prenotazioni in modo PERMANENTE. Per confermare, inserisci la password.'),
            const SizedBox(height: 16),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(child: const Text('ANNULLA'), onPressed: () => Navigator.of(context).pop()),
          TextButton(
            child: const Text('CONFERMA E CANCELLA', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              if (passwordController.text == 'EstateSdraiata') {
                final snapshot = await FirebaseFirestore.instance.collection('bookings').get();
                for (var doc in snapshot.docs) { await doc.reference.delete(); }
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tutte le prenotazioni sono state cancellate.')));
                }
              } else {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password errata.')));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showPasswordDialogForEditor(BuildContext context) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accesso Editor Spiaggia'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Per modificare la mappa della spiaggia, inserisci la password.'),
            const SizedBox(height: 16),
            TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(child: const Text('ANNULLA'), onPressed: () => Navigator.of(dialogContext).pop()),
          ElevatedButton(
            child: const Text('CONFERMA'),
            onPressed: () async {
              if (passwordController.text == 'EstateSdraiata') {
                Navigator.of(dialogContext).pop();
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const BeachEditorScreen()));
                _loadBeachConfiguration();
              } else {
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password errata.')));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _startNewBooking(BuildContext context) async {
    if (_isLoading) return;
    if (_beachSectors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prima crea una mappa della spiaggia dall\'editor!')));
      return;
    }
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Seleziona il periodo di prenotazione',
      locale: const Locale('it', 'IT'),
    );
    if (selectedRange != null && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => MapScreen(filterDateRange: selectedRange, beachSectors: _beachSectors)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bagni Carla 98'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _showSearch(context), tooltip: 'Cerca Prenotazione'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          CustomPaint(size: Size.infinite, painter: StripedBackgroundPainter()),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 200, child: Center(child: Text('BAGNI CARLA 98', textAlign: TextAlign.center, style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.green.shade800)))),
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: () => _startNewBooking(context), child: const Text('Nuova Prenotazione')),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ArriviOggiScreen())), child: const Text('Arrivi')),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => _showSearch(context), child: const Text('Modifica o Cancella Prenotazione')),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => _showPasswordDialogForEditor(context), child: const Text('Editor Mappa Spiaggia')),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => _showResetDialog(context),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                    child: const Text('Reset Stagione', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BookingSearchDelegate extends SearchDelegate<Booking?> {
  final List<Booking> allBookings;
  BookingSearchDelegate(this.allBookings);

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) => _buildResultsList();
  @override
  Widget buildSuggestions(BuildContext context) => _buildResultsList();

  Widget _buildResultsList() {
    if (query.isEmpty) return const Center(child: Text('Digita un nome per cercare.'));
    final results = allBookings.where((b) => b.clientName.toLowerCase().contains(query.toLowerCase()));
    if (results.isEmpty) return const Center(child: Text('Nessuna prenotazione trovata.'));
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final booking = results.elementAt(index);
        String displayId = booking.umbrellaId;
        if (booking.umbrellaId.startsWith('Tende-')) {
          displayId = booking.umbrellaId.replaceFirst('Tende-', '');
        } else {
          displayId = booking.umbrellaId.split('-').last;
        }
        return ListTile(
          title: Text('${booking.clientName} - Ombrellone: $displayId'),
          subtitle: Text('Periodo: ${DateFormat('dd/MM').format(booking.startDate)} - ${DateFormat('dd/MM').format(booking.endDate)}\nSettore: ${booking.umbrellaId.split('-').first}'),
          isThreeLine: true,
          onTap: () => close(context, booking),
        );
      },
    );
  }
}
