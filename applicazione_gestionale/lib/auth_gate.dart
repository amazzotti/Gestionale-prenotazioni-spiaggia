import 'dart:async';

import 'package:flutter/material.dart';

import 'app_version.dart';
import 'booking_repository.dart';
import 'device_service.dart';

/// Decide cosa mostrare, senza schermata di login:
/// - telefono approvato -> l'app;
/// - telefono nuovo -> schermata "in attesa di approvazione".
///
/// I telefoni approvati sono nella collezione `dispositivi` (campo `ruolo`:
/// 'admin' oppure 'staff'). Solo gli admin vedono editor mappa, reset stagione
/// e la gestione dei telefoni.
class AuthGate extends StatefulWidget {
  final Widget Function(BuildContext context, {required bool isAdmin}) builder;
  const AuthGate({super.key, required this.builder});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  DeviceService get _devices => DeviceService.instance;

  String? _uid;
  String? _error;
  StreamSubscription<ApprovedDevice?>? _sub;
  ApprovedDevice? _device;
  bool _checked = false;
  bool? _startedAsAdmin;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _error = null;
      _checked = false;
    });
    try {
      final uid = await _devices.ensureSignedIn();
      await _sub?.cancel();
      _sub = _devices.watchMyDevice(uid).listen(
        _onDevice,
        onError: (Object e) {
          // Le regole negano la lettura solo se qualcosa non va: si tratta come "non approvato".
          debugPrint('Stato telefono non leggibile: $e');
          _onDevice(null);
        },
      );
      if (mounted) setState(() => _uid = uid);
    } catch (e) {
      if (mounted) setState(() => _error = 'Nessuna connessione a internet.\n($e)');
    }
  }

  Future<void> _onDevice(ApprovedDevice? device) async {
    final repo = BookingRepository.instance;
    if (device == null) {
      await repo.stop();
      _startedAsAdmin = null;
    } else if (_startedAsAdmin != device.isAdmin || !repo.isStarted) {
      _startedAsAdmin = device.isAdmin;
      await repo.start(isAdmin: device.isAdmin);
    }
    if (mounted) {
      setState(() {
        _device = device;
        _checked = true;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    BookingRepository.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _MessageScreen(icon: Icons.wifi_off, message: _error!, actionLabel: 'RIPROVA', onAction: _connect);
    }
    if (_uid == null || !_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final device = _device;
    if (device == null) return WaitingApprovalScreen(uid: _uid!);
    return widget.builder(context, isAdmin: device.isAdmin);
  }
}

/// Telefono non ancora approvato: chiede un nome e invia la richiesta.
/// Si sblocca da solo appena un telefono admin lo approva.
class WaitingApprovalScreen extends StatefulWidget {
  final String uid;
  const WaitingApprovalScreen({super.key, required this.uid});

  @override
  State<WaitingApprovalScreen> createState() => _WaitingApprovalScreenState();
}

class _WaitingApprovalScreenState extends State<WaitingApprovalScreen> {
  final _name = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    DeviceService.instance.hasPendingRequest(widget.uid).then((sent) {
      if (mounted && sent) setState(() => _sent = true);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DeviceService.instance.requestAccess(widget.uid, _name.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Richiesta non inviata: controlla la connessione.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = DeviceService.shortCode(widget.uid);
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
                  const SizedBox(height: 24),
                  Text(
                    _sent ? 'Richiesta inviata!' : 'Questo telefono non è ancora abilitato',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sent
                        ? 'Chiedi a chi gestisce il gestionale di approvarlo dal suo telefono, in "Telefoni".\n'
                            'L\'app si aprirà da sola appena approvato.'
                        : 'Scrivi un nome per riconoscerlo e invia la richiesta.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(children: [
                        const Text('Codice del telefono'),
                        Text(code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_sent) ...[
                    TextField(
                      controller: _name,
                      maxLength: DeviceService.maxNameLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nome del telefono (es. Telefono di mamma)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _busy ? null : _send,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('CHIEDI L\'ACCESSO', style: TextStyle(fontSize: 16)),
                    ),
                  ] else
                    const Center(child: CircularProgressIndicator()),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Colors.red.shade800), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  const AppVersionText(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
