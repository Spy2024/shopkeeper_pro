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
}
