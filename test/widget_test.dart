import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/main.dart';

void main() {
  testWidgets('app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const ShopkeeperProApp());
    expect(find.text('Shopkeeper Pro'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
  });
}
