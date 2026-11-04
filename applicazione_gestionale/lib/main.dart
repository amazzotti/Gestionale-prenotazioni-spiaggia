import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app_version.dart';
import 'arrivi_oggi_screen.dart';
import 'auth_gate.dart';
import 'availability.dart';
import 'beach_editor_screen.dart';
import 'booking_repository.dart';
import 'devices_screen.dart';
import 'layout_repository.dart';
import 'map_screen.dart';
import 'stats_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it');
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
  final Widget? home;
  const MyApp({super.key, this.home});

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
      supportedLocales: const [Locale('it', 'IT')],
      locale: const Locale('it', 'IT'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: home ?? AuthGate(builder: (context, {required isAdmin}) => HomeScreen(isAdmin: isAdmin)),
    );
  }
}

class HomeScreen extends StatefulWidget {
  /// Gli admin vedono anche Editor mappa e Reset stagione.
  final bool isAdmin;
  const HomeScreen({super.key, required this.isAdmin});

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
      final sectors = await LayoutRepository.instance.loadSectors();
      if (mounted) setState(() => _beachSectors = sectors);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore caricamento mappa: $e')));
        setState(() => _beachSectors = []);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _ensureMap(BuildContext context) {
    if (_isLoading) return false;
    if (_beachSectors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.isAdmin ? 'Prima crea la mappa della spiaggia dall\'editor!' : 'La mappa della spiaggia non è ancora stata creata.'),
      ));
      return false;
    }
    return true;
  }

  Future<void> _showSearch(BuildContext context) async {
    if (!_ensureMap(context)) return;
    final allBookings = BookingRepository.instance.bookings.value;
    if (allBookings == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prenotazioni in caricamento, riprova tra un attimo.')));
      return;
    }
    final selected = await showSearch<Booking?>(context: context, delegate: BookingSearchDelegate(allBookings));
    if (selected != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapScreen(
            highlightUmbrellaId: selected.umbrellaId,
            filterDateRange: selected.range,
            beachSectors: _beachSectors,
          ),
        ),
      );
    }
  }

  Future<void> _startNewBooking(BuildContext context) async {
    if (!_ensureMap(context)) return;
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: BookingRepository.instance.windowStart,
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Seleziona il periodo di prenotazione',
      locale: const Locale('it', 'IT'),
    );
    if (selectedRange != null && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => MapScreen(filterDateRange: selectedRange, beachSectors: _beachSectors)));
    }
  }

  void _openTodayMap(BuildContext context) {
    if (!_ensureMap(context)) return;
    Navigator.push(context, MaterialPageRoute(builder: (context) => MapScreen(beachSectors: _beachSectors)));
  }

  void _openStats(BuildContext context) {
    if (!_ensureMap(context)) return;
    Navigator.push(context, MaterialPageRoute(builder: (context) => StatsScreen(beachSectors: _beachSectors)));
  }

  /// Reset stagione: solo admin, e bisogna scrivere RESET per confermare.
  Future<void> _showResetDialog(BuildContext context) async {
    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Resettare la Stagione?'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Questa azione cancellerà TUTTE le prenotazioni in modo PERMANENTE.\n\nPer confermare scrivi RESET qui sotto.'),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Scrivi RESET', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(child: const Text('ANNULLA'), onPressed: () => Navigator.of(dialogContext).pop(false)),
            TextButton(
              onPressed: confirmController.text.trim().toUpperCase() == 'RESET' ? () => Navigator.of(dialogContext).pop(true) : null,
              child: const Text('CANCELLA TUTTO', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    confirmController.dispose();
    if (confirmed != true || !context.mounted) return;

    try {
      final count = await BookingRepository.instance.deleteAllBookings();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cancellate $count prenotazioni.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore durante il reset: $e')));
      }
    }
  }

  Future<void> _openEditor(BuildContext context) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => const BeachEditorScreen()));
    _loadBeachConfiguration();
  }

  Widget _todaySummary() {
    return ValueListenableBuilder<List<Booking>?>(
      valueListenable: BookingRepository.instance.bookings,
      builder: (context, bookings, _) {
        if (bookings == null || _beachSectors.isEmpty) return const SizedBox(height: 8);
        final today = BookingRepository.instance.today;
        final occupancy = occupancyOn(today, _beachSectors, bookings);
        final total = occupancy.fold<int>(0, (s, o) => s + o.total);
        final occupied = occupancy.fold<int>(0, (s, o) => s + o.occupied);
        Widget tile(String value, String label, IconData icon) => Expanded(
              child: Column(children: [
                Icon(icon, color: Colors.green.shade800),
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ]),
            );
        return Card(
          color: Colors.white.withValues(alpha: 0.9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(children: [
              Text('Oggi, ${DateFormat('EEEE d MMMM', 'it').format(today)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                tile('$occupied/$total', 'ombrelloni occupati', Icons.beach_access),
                tile('${arrivalsOn(today, bookings).length}', 'arrivi', Icons.login),
                tile('${departuresOn(today, bookings).length}', 'partenze', Icons.logout),
              ]),
            ]),
          ),
        );
      },
    );
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
                RefreshIndicator(
                  onRefresh: _loadBeachConfiguration,
                  child: ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      SizedBox(
                        height: 110,
                        child: Center(
                          child: Text('BAGNI CARLA 98',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                        ),
                      ),
                      _todaySummary(),
                      const SizedBox(height: 16),
                      _menuButton(Icons.add_circle_outline, 'Nuova Prenotazione', () => _startNewBooking(context)),
                      _menuButton(Icons.map_outlined, 'Mappa di Oggi', () => _openTodayMap(context)),
                      _menuButton(Icons.people_outline, 'Arrivi e Partenze',
                          () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ArriviOggiScreen()))),
                      _menuButton(Icons.search, 'Cerca, Modifica o Cancella', () => _showSearch(context)),
                      _menuButton(Icons.bar_chart, 'Incassi e Statistiche', () => _openStats(context)),
                      if (widget.isAdmin) ...[
                        const Divider(height: 32),
                        _menuButton(Icons.edit_location_alt_outlined, 'Editor Mappa Spiaggia', () => _openEditor(context)),
                        _menuButton(Icons.smartphone, 'Telefoni',
                            () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DevicesScreen()))),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _showResetDialog(context),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                          child: const Text('Reset Stagione', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const AppVersionText(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _menuButton(IconData icon, String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), alignment: Alignment.centerLeft),
      ),
    );
  }
}

class BookingSearchDelegate extends SearchDelegate<Booking?> {
  final List<Booking> allBookings;
  BookingSearchDelegate(this.allBookings) : super(searchFieldLabel: 'Nome, telefono o n° ombrellone');

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) => _buildResultsList();
  @override
  Widget buildSuggestions(BuildContext context) => _buildResultsList();

  Widget _buildResultsList() {
    if (query.trim().isEmpty) return const Center(child: Text('Digita un nome, un telefono o il numero dell\'ombrellone.'));
    final results = searchBookings(query, allBookings);
    if (results.isEmpty) return const Center(child: Text('Nessuna prenotazione trovata.'));
    final fmt = DateFormat('dd/MM');
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final booking = results[index];
        return ListTile(
          title: Text('${booking.clientName} - Ombrellone: ${booking.umbrellaLabel}'),
          subtitle: Text('Periodo: ${fmt.format(booking.startDate)} - ${fmt.format(booking.endDate)}\nSettore: ${booking.sectorName}'
              '${booking.amountDue > 0 ? ' · da incassare ${formatEuro(booking.amountDue)}' : ''}'),
          isThreeLine: true,
          onTap: () => close(context, booking),
        );
      },
    );
  }
}
