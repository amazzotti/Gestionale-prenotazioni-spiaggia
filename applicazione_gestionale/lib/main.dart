import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'arrivi_oggi_screen.dart';
import 'map_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

// --- Pittore per lo sfondo a strisce ---
class StripedBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintGreen = Paint()..color = Colors.green.withOpacity(0.1);
    final paintWhite = Paint()..color = Colors.white.withOpacity(0.1);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const InitialLoadingScreen(),
    );
  }
}

class InitialLoadingScreen extends StatefulWidget {
  const InitialLoadingScreen({super.key});

  @override
  State<InitialLoadingScreen> createState() => _InitialLoadingScreenState();
}

class _InitialLoadingScreenState extends State<InitialLoadingScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Firebase.initializeApp();
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => isLoggedIn ? const HomeScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;

  void _login() async {
    const hardcodedUsername = 'Bagni Carla 98';
    const hardcodedPassword = 'EstateSdraiata';

    final username = _usernameController.text;
    final password = _passwordController.text;

    if (username == hardcodedUsername && password == hardcodedPassword) {
      if (_rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credenziali non valide')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accesso Gestionale'),
      ),
      body: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: StripedBackgroundPainter(),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                      labelText: 'Username', border: OutlineInputBorder(), fillColor: Colors.white70, filled: true),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password', border: OutlineInputBorder(), fillColor: Colors.white70, filled: true),
                ),
                CheckboxListTile(
                  title: const Text("Ricordami"),
                  value: _rememberMe,
                  onChanged: (newValue) {
                    setState(() {
                      _rememberMe = newValue!;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _login,
                  child: const Text('Login'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _showSearch(BuildContext context) async {
    final allUmbrellas = beachSectors.expand((s) => s.umbrellas).toList();
    final snapshot = await FirebaseFirestore.instance.collection('bookings').get();
    final bookingsMap = <String, Booking>{};
    for (var doc in snapshot.docs) {
      try {
        bookingsMap[doc.id] = Booking.fromMap(doc.data() as Map<String, dynamic>);
      } catch (e) { /* Ignora */ }
    }
    for (var umbrella in allUmbrellas) {
      umbrella.booking = bookingsMap[umbrella.id];
    }

    if (!context.mounted) return;
    final selectedUmbrella = await showSearch<Umbrella?>(
      context: context,
      delegate: BookingSearchDelegate(allUmbrellas),
    );

    if (selectedUmbrella != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapScreen(highlightUmbrellaId: selectedUmbrella.id),
        ),
      );
    }
  }

  void _showResetDialog(BuildContext context) {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Resettare la Stagione?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Questa azione cancellerà TUTTE le prenotazioni in modo PERMANENTE. Per confermare, inserisci la password.'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(child: const Text('ANNULLA'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text('CONFERMA E CANCELLA', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                if (passwordController.text == 'EstateSdraiata') {
                  final snapshot = await FirebaseFirestore.instance.collection('bookings').get();
                  for (var doc in snapshot.docs) {
                    await doc.reference.delete();
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Tutte le prenotazioni sono state cancellate.')),
                    );
                  }
                } else {
                  if (context.mounted) {
                     Navigator.of(context).pop();
                     ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password errata.')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // --- NUOVO FLUSSO DI PRENOTAZIONE ---
  void _startNewBooking(BuildContext context) async {
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Seleziona il periodo di prenotazione',
    );

    if (selectedRange != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapScreen(filterDateRange: selectedRange),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bagni Carla 98'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearch(context),
            tooltip: 'Cerca Prenotazione',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: StripedBackgroundPainter(),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 200,
                    child: Center(
                        child: Text(
                      'BAGNI CARLA 98',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800),
                    )),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => _startNewBooking(context),
                    child: const Text('Nuova Prenotazione'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ArriviOggiScreen()),
                      );
                    },
                    child: const Text('Arrivi di Oggi'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _showSearch(context),
                    child: const Text('Modifica o Cancella Prenotazione'),
                  ),
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
