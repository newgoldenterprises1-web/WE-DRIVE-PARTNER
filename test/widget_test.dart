import 'package:flutter_test/flutter_test.dart';
import 'package:we_drive_partner/main.dart';

void main() {
  testWidgets('WE DRIVE Partner starts', (WidgetTester tester) async {
    await tester.pumpWidget(const WeDrivePartnerApp());
    expect(find.text('WE DRIVE'), findsWidgets);
  });
}
