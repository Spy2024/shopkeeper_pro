import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';

void main() {
  testWidgets('billing summary renders expected total', (tester) async {
    final bill = Bill(
      id: 'b1',
      date: DateTime(2026, 10, 1),
      items: [
        BillItem(productName: 'Tea', quantity: 2, unitPrice: 150),
      ],
      discount: 10,
      taxPercent: 17,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('New Bill'),
              Text('Subtotal: ${bill.subtotal.toStringAsFixed(2)}'),
              Text('Total: ${bill.grandTotal.toStringAsFixed(2)}'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('New Bill'), findsOneWidget);
    expect(find.text('Subtotal: 300.00'), findsOneWidget);
    expect(find.text('Total: 339.30'), findsOneWidget);
  });
}
