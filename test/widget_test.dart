
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bitacora/main.dart';

void main() {
  testWidgets('Bitacora initial load test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BitacoraApp()));
    await tester.pumpAndSettle();
    
    // Verify that our app bar title is rendered
    expect(find.text('Bitacora TMS'), findsWidgets);
  });
}
