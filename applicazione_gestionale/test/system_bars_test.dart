import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicazione_gestionale/system_bars.dart';

void main() {
  testWidgets('il fondo delle schermate resta sopra i tasti di Android', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.0;
    // barra dei tasti alta 48: su un telefono vero Android la indica in entrambi i valori
    tester.view.padding = const FakeViewPadding(bottom: 96);
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    addTearDown(tester.view.reset);

    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SystemBarsSafeArea(child: child!),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ElevatedButton(onPressed: () => tapped = true, child: const Text('Reset Stagione')),
        ),
      ),
    ));

    const screenHeight = 1100.0;
    expect(tester.getBottomLeft(find.text('Reset Stagione')).dy, lessThanOrEqualTo(screenHeight - 48));
    await tester.tap(find.text('Reset Stagione'));
    expect(tapped, isTrue);
  });

  testWidgets('anche i pannelli che salgono dal basso restano sopra i tasti', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(bottom: 96);
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SystemBarsSafeArea(child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const ListTile(title: Text('Ultima voce'))),
              child: const Text('apri'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('Ultima voce')).dy, lessThanOrEqualTo(1100 - 48));
  });
}
