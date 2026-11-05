import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dalle versioni recenti di Android (15 in poi, es. i Samsung aggiornati) le app
/// disegnano anche sotto la barra con i tasti indietro / home / app recenti.
/// Senza questo widget il fondo delle schermate finiva sotto quei tasti e non si
/// poteva toccare.
///
/// Lascia libero lo spazio della barra in fondo (e ai lati in orizzontale), lo
/// colora di bianco e rende scuri i tasti, così si vedono bene.
/// Si mette una volta sola, in `MaterialApp.builder`: vale per tutte le schermate,
/// le finestre e i pannelli che salgono dal basso.
class SystemBarsSafeArea extends StatelessWidget {
  final Widget child;
  const SystemBarsSafeArea({super.key, required this.child});

  static const overlayStyle = SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.white,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: ColoredBox(
        color: Colors.white,
        child: SafeArea(
          top: false, // in alto ci pensano le barre delle schermate
          maintainBottomViewPadding: true,
          child: child,
        ),
      ),
    );
  }
}
