import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:applicazione_gestionale/app_version.dart';

void main() {
  test('formatVersion mostra V e toglie il numero di build', () {
    expect(formatVersion('1.0.0+1'), 'V1.0.0');
    expect(formatVersion('2.3.10'), 'V2.3.10');
  });

  testWidgets('AppVersionText mostra la versione installata', (tester) async {
    PackageInfo.setMockInitialValues(appName: 'a', packageName: 'b', version: '1.2.3', buildNumber: '7', buildSignature: '');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppVersionText())));
    await tester.pumpAndSettle();
    expect(find.text('V1.2.3'), findsOneWidget);
    expect(find.text('Ideata e progettata da Alessandro Mazzotti'), findsOneWidget);
    final credit = tester.widget<Text>(find.text(authorCredit));
    expect(credit.style?.fontStyle, FontStyle.italic);
  });
}
