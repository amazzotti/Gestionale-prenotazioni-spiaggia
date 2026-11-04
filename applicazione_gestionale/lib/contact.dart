import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'availability.dart';

/// Apre il telefono per chiamare il numero.
Future<bool> callNumber(String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: 'tel', path: digits));
  } catch (_) {
    return false;
  }
}

/// Apre WhatsApp sulla chat del numero, con un messaggio già scritto (facoltativo).
Future<bool> openWhatsApp(String phone, {String? message}) async {
  final number = whatsappNumber(phone);
  if (number == null) return false;
  final uri = Uri.https('wa.me', '/$number', message == null ? null : {'text': message});
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Pulsanti "Chiama" e "WhatsApp". Non mostra nulla se il numero non è valido.
class ContactButtons extends StatelessWidget {
  final String phone;
  final String? whatsappMessage;
  const ContactButtons({super.key, required this.phone, this.whatsappMessage});

  void _failed(BuildContext context, String what) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Impossibile aprire $what.')));
  }

  @override
  Widget build(BuildContext context) {
    if (whatsappNumber(phone) == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.call),
          color: Colors.blue.shade700,
          tooltip: 'Chiama',
          onPressed: () async {
            if (!await callNumber(phone) && context.mounted) _failed(context, 'il telefono');
          },
        ),
        IconButton(
          icon: const Icon(Icons.chat),
          color: Colors.green.shade700,
          tooltip: 'WhatsApp',
          onPressed: () async {
            if (!await openWhatsApp(phone, message: whatsappMessage) && context.mounted) _failed(context, 'WhatsApp');
          },
        ),
      ],
    );
  }
}
