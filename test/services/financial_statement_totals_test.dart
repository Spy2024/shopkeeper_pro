import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/services/backup_restore_service.dart';

void main() {
  test('empty financial records produce zero totals', () {
    final totals = FinancialStatementTotals.fromRecords(
      billRows: const [],
      expenseRows: const [],
      returnRows: const [],
      productRows: const [],
      dailySalesRows: const [],
    );
    expect(totals.billedSales, 0);
    expect(totals.netSales, 0);
    expect(totals.costOfGoods, 0);
    expect(totals.netProfit, 0);
  });

  test('financial totals reconcile a taxed sale, partial refund, COGS and expense', () {
    final totals = FinancialStatementTotals.fromRecords(
      billRows: const [
        {'id': 'bill-1', 'subtotal': 100.0, 'discount': 0.0, 'taxPercent': 10.0},
      ],
      expenseRows: const [
        {'amount': 5.0},
      ],
      returnRows: const [
        {'billId': 'bill-1', 'refundAmount': 55.0},
      ],
      productRows: const [
        {'stockQuantity': 3, 'costPrice': 20.0},
      ],
      dailySalesRows: const [
        {'source': 'pos', 'costPrice': 20.0, 'quantity': 2},
        {'source': 'return', 'costPrice': -20.0, 'quantity': 1},
        // Manual sales must not be counted as POS COGS.
        {'source': 'manual', 'costPrice': 9.0, 'quantity': 4},
      ],
    );

    expect(totals.billedSales, closeTo(110.0, 0.001));
    expect(totals.refunds, closeTo(55.0, 0.001));
    expect(totals.netSales, closeTo(55.0, 0.001));
    expect(totals.taxCollected, closeTo(5.0, 0.001));
    expect(totals.costOfGoods, closeTo(20.0, 0.001));
    expect(totals.grossProfit, closeTo(30.0, 0.001));
    expect(totals.expenses, closeTo(5.0, 0.001));
    expect(totals.netProfit, closeTo(25.0, 0.001));
    expect(totals.currentStockValue, closeTo(60.0, 0.001));
    expect(totals.billCount, 1);
    expect(totals.productCount, 1);
  });

  test('discount cannot make taxable subtotal negative', () {
    final totals = FinancialStatementTotals.fromRecords(
      billRows: const [
        {'id': 'bill-1', 'subtotal': 50.0, 'discount': 80.0, 'taxPercent': 15.0},
      ],
      expenseRows: const [],
      returnRows: const [],
      productRows: const [],
      dailySalesRows: const [],
    );
    expect(totals.billedSales, 0);
    expect(totals.taxCollected, 0);
  });
}
