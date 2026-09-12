import 'package:flutter_test/flutter_test.dart';
import 'package:we_drive_partner/main.dart';

void main() {
  testWidgets('WE DRIVE Partner starts', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('WE DRIVE'), findsOneWidget);
    expect(
      find.text('Your Car. Your Comfort. Our Chauffeur.'),
      findsOneWidget,
    );

    // Complete the splash delay so no timer remains pending when the test ends.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}
