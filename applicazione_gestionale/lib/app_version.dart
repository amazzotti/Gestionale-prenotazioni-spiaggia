import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Versione dell'app nel formato "V1.0.0".
/// Il numero viene da `version:` in pubspec.yaml, aggiornato in automatico da `rilascia.bat`.
String formatVersion(String version) => 'V${version.split('+').first}';

/// Firma dell'autore, in fondo alle schermate sotto la versione.
const String authorCredit = 'Ideata e progettata da Alessandro Mazzotti';

/// Versione e firma dell'autore in piccolo, da mettere in fondo alle schermate.
class AppVersionText extends StatefulWidget {
  final Color? color;
  const AppVersionText({super.key, this.color});

  @override
  State<AppVersionText> createState() => _AppVersionTextState();
}

class _AppVersionTextState extends State<AppVersionText> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Colors.grey.shade700;
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (version == null || version.isEmpty)
              const SizedBox(height: 16)
            else
              Text(formatVersion(version), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(height: 2),
            Text(
              authorCredit,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: color),
            ),
          ],
        );
      },
    );
  }
}
