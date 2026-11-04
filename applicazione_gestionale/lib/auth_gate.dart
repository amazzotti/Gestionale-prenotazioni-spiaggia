import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'booking_repository.dart';

/// Decide cosa mostrare: login, "non autorizzato" oppure l'app.
///
/// Gli utenti autorizzati sono i documenti della collezione `utenti`,
/// con ID = email in minuscolo e campo `ruolo` ('admin' oppure 'staff').
/// Solo gli admin possono modificare la mappa e resettare la stagione.
class AuthGate extends StatelessWidget {
  final Widget Function(BuildContext context, {required bool isAdmin}) builder;
  const AuthGate({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return _RoleLoader(key: ValueKey(user.uid), user: user, builder: builder);
      },
    );
  }
}

class _RoleLoader extends StatefulWidget {
  final User user;
  final Widget Function(BuildContext context, {required bool isAdmin}) builder;
  const _RoleLoader({super.key, required this.user, required this.builder});

  @override
  State<_RoleLoader> createState() => _RoleLoaderState();
}

class _RoleLoaderState extends State<_RoleLoader> {
  bool _loading = true;
  bool _authorized = false;
  bool _isAdmin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = (widget.user.email ?? '').toLowerCase();
      final doc = await FirebaseFirestore.instance.collection('utenti').doc(email).get();
      if (doc.exists) {
        _authorized = true;
        _isAdmin = doc.data()?['ruolo'] == 'admin';
        await BookingRepository.instance.start(isAdmin: _isAdmin);
      } else {
        _authorized = false;
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _authorized = false;
      } else {
        _error = 'Errore di connessione: ${e.message ?? e.code}';
      }
    } catch (e) {
      _error = 'Errore: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    BookingRepository.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return _MessageScreen(
        icon: Icons.wifi_off,
        message: _error!,
        actionLabel: 'RIPROVA',
        onAction: _loadRole,
      );
    }
    if (!_authorized) {
      return _MessageScreen(
        icon: Icons.block,
        message: 'L\'account ${widget.user.email} non è autorizzato a usare il gestionale.',
        actionLabel: 'ESCI',
        onAction: () => FirebaseAuth.instance.signOut(),
      );
    }
    return widget.builder(context, isAdmin: _isAdmin);
  }
}

class _MessageScreen extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  const _MessageScreen({required this.icon, required this.message, required this.actionLabel, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
          ]),
        ),
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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Email non valida.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email o password errate.';
      case 'user-disabled':
        return 'Questo account è stato disattivato.';
      case 'too-many-requests':
        return 'Troppi tentativi. Riprova tra qualche minuto.';
      case 'network-request-failed':
        return 'Nessuna connessione a internet.';
      default:
        return 'Accesso non riuscito (${e.code}).';
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Inserisci email e password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Scrivi la tua email e poi premi "Password dimenticata?".');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Se l\'account esiste, riceverai un\'email a $email per reimpostare la password.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.beach_access, size: 64, color: Colors.green.shade700),
                  const SizedBox(height: 12),
                  Text('BAGNI CARLA 98',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Colors.red.shade800), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _busy ? null : _login,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ACCEDI', style: TextStyle(fontSize: 16)),
                  ),
                  TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('Password dimenticata?')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
