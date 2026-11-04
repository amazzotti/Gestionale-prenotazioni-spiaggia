import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Versione dell'app nel formato "V1.0.0".
/// Il numero viene da `version:` in pubspec.yaml, aggiornato in automatico da `rilascia.bat`.
String formatVersion(String version) => 'V${version.split('+').first}';

/// Scritta piccola con la versione, da mettere in fondo alle schermate.
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
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        if (version == null || version.isEmpty) return const SizedBox(height: 16);
        return Text(
          formatVersion(version),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: widget.color ?? Colors.grey.shade700),
        );
      },
    );
  }
}
