// Test di base: verifica che l'app si avvii senza errori.
import 'package:flutter_test/flutter_test.dart';

import 'package:sermaps_driver/main.dart';

void main() {
  testWidgets('L\'app si avvia', (WidgetTester tester) async {
    await tester.pumpWidget(const SerMapsApp());
    expect(find.text('SerMaps Driver'), findsOneWidget);
  });
}
