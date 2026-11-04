import 'package:flutter/material.dart';

import 'device_service.dart';
import 'help_screen.dart';

/// Gestione dei telefoni (solo admin): approvare quelli nuovi e togliere l'accesso.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  DeviceService get _service => DeviceService.instance;

  void _message(BuildContext context, String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _approve(BuildContext context, AccessRequest request) async {
    final nameController = TextEditingController(text: request.name);
    var role = DeviceRole.admin;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Approvare il telefono?'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Controlla che sul telefono compaia il codice ${request.code}.'),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              maxLength: DeviceService.maxNameLength,
              decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
            ),
            RadioGroup<String>(
              groupValue: role,
              onChanged: (v) => setState(() => role = v ?? DeviceRole.admin),
              child: const Column(children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: DeviceRole.admin,
                  title: Text('Famiglia: tutto'),
                  subtitle: Text('Anche editor mappa, reset e telefoni'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: DeviceRole.staff,
                  title: Text('Solo prenotazioni'),
                  subtitle: Text('Prenotazioni, arrivi e incassi'),
                ),
              ]),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ANNULLA')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('APPROVA')),
          ],
        ),
      ),
    );
    final name = nameController.text;
    nameController.dispose();
    if (ok != true || !context.mounted) return;
    try {
      await _service.approve(request, role: role, name: name);
      if (context.mounted) _message(context, '${DeviceService.cleanName(name)} approvato.');
    } catch (e) {
      if (context.mounted) _message(context, 'Errore: $e');
    }
  }

  Future<void> _reject(BuildContext context, AccessRequest request) async {
    try {
      await _service.reject(request);
    } catch (e) {
      if (context.mounted) _message(context, 'Errore: $e');
    }
  }

  Future<void> _revoke(BuildContext context, ApprovedDevice device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Togliere l\'accesso?'),
        content: Text('"${device.name}" non potrà più aprire il gestionale finché non lo approvi di nuovo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ANNULLA')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('TOGLI ACCESSO', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await _service.revoke(device);
      if (context.mounted) _message(context, 'Accesso tolto a ${device.name}.');
    } catch (e) {
      if (context.mounted) _message(context, '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _service.currentUid;
    return Scaffold(
      appBar: AppBar(title: const Text('Telefoni'), backgroundColor: Colors.green, actions: const [HelpButton(HelpTopic.telefoni)]),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text('In attesa di approvazione', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          StreamBuilder<List<AccessRequest>>(
            stream: _service.watchRequests(),
            builder: (context, snap) {
              final list = snap.data;
              if (list == null) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Nessuna richiesta. Per aggiungere un telefono, installa l\'app e premi "Chiedi l\'accesso".'),
                );
              }
              return Column(children: [
                for (final r in list)
                  Card(
                    color: Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        Text('Codice ${r.code}', style: const TextStyle(letterSpacing: 1.5)),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TextButton(onPressed: () => _reject(context, r), child: const Text('RIFIUTA')),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _approve(context, r),
                            icon: const Icon(Icons.check),
                            label: const Text('APPROVA'),
                          ),
                        ]),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Text('Telefoni abilitati', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          StreamBuilder<List<ApprovedDevice>>(
            stream: _service.watchDevices(),
            builder: (context, snap) {
              final list = snap.data;
              if (list == null) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              return Column(children: [
                for (final d in list)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.smartphone, color: d.isAdmin ? Colors.green.shade800 : Colors.blueGrey),
                      title: Text(d.uid == myUid ? '${d.name} (questo telefono)' : d.name),
                      subtitle: Text('${d.isAdmin ? 'Famiglia: tutto' : 'Solo prenotazioni'} · codice ${DeviceService.shortCode(d.uid)}'),
                      trailing: d.uid == myUid
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.block, color: Colors.red),
                              tooltip: 'Togli accesso',
                              onPressed: () => _revoke(context, d),
                            ),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
