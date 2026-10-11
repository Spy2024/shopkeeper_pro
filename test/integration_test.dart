import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/models/daily_sale.dart';
import 'package:shopkeeper_pro/models/product.dart';
import 'package:shopkeeper_pro/models/supplier.dart';
import 'package:shopkeeper_pro/providers/pos_provider.dart';
import 'package:shopkeeper_pro/providers/inventory_provider.dart';
import 'package:shopkeeper_pro/providers/supplier_provider.dart';
import 'package:shopkeeper_pro/providers/sales_provider.dart';
import 'package:shopkeeper_pro/services/backup_restore_service.dart';
import 'package:shopkeeper_pro/services/sync_service.dart';

void main() {
  group('Shopkeeper business-flow tests', () {
    test('authentication phone format expectation', () {
      expect(RegExp(r'^\+\d{8,15}$').hasMatch('+923334455667'), isTrue);
    });

    test('inventory stock calculation', () {
      final p = Product(id: 'p1', name: 'Tea', category: 'Grocery',
        stockQuantity: 50, costPrice: 80, sellingPrice: 120);
      expect(p.stockQuantity - 2, 48);
    });

    test('checkout validation blocks expired products but allows valid stock', () {
      final expired = Product(
        id: 'expired', name: 'Expired milk', category: 'Dairy',
        stockQuantity: 4, costPrice: 80, sellingPrice: 120,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(() => validateProductCanBeSold(expired), throwsStateError);

      final valid = Product(
        id: 'valid', name: 'Fresh milk', category: 'Dairy',
        stockQuantity: 4, costPrice: 80, sellingPrice: 120,
        expiryDate: DateTime.now().add(const Duration(days: 1)),
      );
      expect(() => validateProductCanBeSold(valid), returnsNormally);
    });

    test('product barcode and expiry survive map round-trip', () {
      final expiry = DateTime.now().add(const Duration(days: 10));
      final product = Product(
        id: 'p-barcode',
        name: 'Milk',
        category: 'Dairy',
        stockQuantity: 8,
        costPrice: 100,
        sellingPrice: 140,
        barcode: '8901234567890',
        expiryDate: expiry,
      );
      final restored = Product.fromMap(product.toMap());
      expect(restored.barcode, '8901234567890');
      expect(restored.expiryDate, expiry);
      expect(restored.expiresWithin30Days, isTrue);
      expect(restored.isExpired, isFalse);
    });

    test('expired products are flagged by date only', () {
      final product = Product(
        id: 'p-expired',
        name: 'Yogurt',
        category: 'Dairy',
        stockQuantity: 2,
        costPrice: 50,
        sellingPrice: 70,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(product.isExpired, isTrue);
      expect(product.expiresWithin30Days, isFalse);
    });

    test('cart keeps different prices for the same product on separate lines', () {
      final pos = PosProvider();
      pos.addItem('Tea', 2, 100, productId: 'tea-id');
      pos.addItem('Tea', 1, 120, productId: 'tea-id');

      expect(pos.cart, hasLength(2));
      expect(pos.cart[0].quantity, 2);
      expect(pos.cart[0].unitPrice, 100);
      expect(pos.cart[1].quantity, 1);
      expect(pos.cart[1].unitPrice, 120);
      expect(pos.subtotal, 320);
    });

    test('cart merges same product only when the unit price matches', () {
      final pos = PosProvider();
      pos.addItem('Tea', 2, 100, productId: 'tea-id');
      pos.addItem('Tea', 3, 100, productId: 'tea-id');

      expect(pos.cart, hasLength(1));
      expect(pos.cart.single.quantity, 5);
      expect(pos.cart.single.unitPrice, 100);
      expect(pos.subtotal, 500);
    });

    test('POS bill calculation', () {
      final bill = Bill(id: 'b1', date: DateTime.now(),
        items: [BillItem(productId: 'p1', productName: 'Tea', quantity: 2, unitPrice: 150),
          BillItem(productId: 'p2', productName: 'Milk', quantity: 1, unitPrice: 120)],
        discount: 20, taxPercent: 17);
      expect(bill.grandTotal, closeTo(468.0, 0.0001));
    });

    test('daily sale margin is correct', () {
      final sale = DailySale(id: 's1', date: DateTime.now(), productName: 'Tea',
        costPrice: 100, salePrice: 150, source: 'pos');
      expect(sale.margin, 50);
    });

    test('daily sale revenue and COGS include sold quantity', () {
      final sale = DailySale(
        id: 's2',
        date: DateTime.now(),
        productName: 'Tea',
        costPrice: 80,
        salePrice: 120,
        quantity: 3,
        source: 'pos',
      );
      expect(sale.revenue, 360);
      expect(sale.costOfGoods, 240);
      expect(sale.margin, 120);
    });

    test('financial statement totals include refunds, COGS and expenses', () {
      final totals = FinancialStatementTotals.fromRecords(
        billRows: [
          {'subtotal': 1000.0, 'discount': 100.0, 'taxPercent': 10.0},
        ],
        expenseRows: [
          {'amount': 80.0},
        ],
        returnRows: [
          {'refundAmount': 110.0},
        ],
        productRows: [
          {'stockQuantity': 5, 'costPrice': 100.0},
        ],
        dailySalesRows: [
          {'costPrice': 300.0, 'quantity': 2, 'source': 'pos'},
          {'costPrice': -300.0, 'quantity': 1, 'source': 'return'},
          // Manual sales are not included in billedSales, so their COGS must
          // not reduce the profit of the POS-only statement.
          {'costPrice': 999.0, 'quantity': 2, 'source': 'manual'},
        ],
      );

      expect(totals.billedSales, closeTo(990.0, 0.001));
      expect(totals.refunds, closeTo(110.0, 0.001));
      expect(totals.netSales, closeTo(880.0, 0.001));
      expect(totals.costOfGoods, closeTo(300.0, 0.001));
      expect(totals.grossProfit, closeTo(580.0, 0.001));
      expect(totals.expenses, closeTo(80.0, 0.001));
      expect(totals.netProfit, closeTo(500.0, 0.001));
      expect(totals.currentStockValue, closeTo(500.0, 0.001));
      expect(totals.billCount, 1);
      expect(totals.productCount, 1);
    });

    test('bill item resolution never substitutes a different product when an ID is present', () {
      final intended = Product(
        id: 'intended', name: 'Tea', category: 'Grocery',
        stockQuantity: 5, costPrice: 80, sellingPrice: 120,
      );
      final sameNameWrongId = Product(
        id: 'other', name: 'Tea', category: 'Grocery',
        stockQuantity: 10, costPrice: 70, sellingPrice: 110,
      );
      expect(
        resolveProductForBillItem(
          BillItem(productId: 'missing-id', productName: 'Tea', quantity: 1, unitPrice: 120),
          [intended, sameNameWrongId],
        ),
        isNull,
      );
      expect(
        resolveProductForBillItem(
          BillItem(productId: 'intended', productName: 'Old display name', quantity: 1, unitPrice: 120),
          [intended, sameNameWrongId],
        )?.id,
        'intended',
      );
    });

    test('return eligibility counts only the same product and unit price', () {
      final bill = Bill(
        id: 'return-bill',
        date: DateTime.now(),
        items: [
          BillItem(productId: 'p1', productName: 'Oil', quantity: 3, unitPrice: 100),
          BillItem(productId: 'p1', productName: 'Oil', quantity: 2, unitPrice: 120),
        ],
      );
      final product = Product(
        id: 'p1', name: 'Oil', category: 'Grocery',
        stockQuantity: 0, costPrice: 70, sellingPrice: 120,
      );
      expect(soldQuantityForReturnLine(
        bill: bill, item: bill.items[0], product: product,
      ), 3);
      expect(soldQuantityForReturnLine(
        bill: bill, item: bill.items[1], product: product,
      ), 2);
    });

    test('refund rejects a line that is not part of the bill', () {
      final bill = Bill(
        id: 'bill-a',
        date: DateTime.now(),
        items: [
          BillItem(productId: 'p1', productName: 'Oil', quantity: 2, unitPrice: 100),
        ],
      );
      expect(
        () => bill.refundFor(
          BillItem(productId: 'p2', productName: 'Rice', quantity: 1, unitPrice: 100),
          1,
        ),
        throwsArgumentError,
      );
      expect(() => bill.refundFor(bill.items.single, 3), throwsArgumentError);
    });

    test('purchase receipt aggregates duplicate product lines', () {
      final tea = Product(
        id: 'tea-id', name: 'Tea', category: 'Grocery',
        stockQuantity: 7, costPrice: 80, sellingPrice: 120,
      );
      final quantities = aggregatePurchaseOrderQuantities(
        items: [
          SupplierOrderItem(productName: 'Tea', requiredQuantity: 3, estimatedPrice: 70),
          SupplierOrderItem(productName: ' tea ', requiredQuantity: 4, estimatedPrice: 75),
        ],
        products: [tea],
      );

      expect(quantities, {'tea-id': 7});
      expect(tea.stockQuantity + quantities['tea-id']!, 14);
    });

    test('purchase receipt rejects missing or ambiguous products', () {
      final tea = Product(
        id: 'tea-id', name: 'Tea', category: 'Grocery',
        stockQuantity: 7, costPrice: 80, sellingPrice: 120,
      );
      expect(
        () => aggregatePurchaseOrderQuantities(
          items: [SupplierOrderItem(productName: 'Coffee', requiredQuantity: 1, estimatedPrice: 50)],
          products: [tea],
        ),
        throwsStateError,
      );
      final duplicateName = Product(
        id: 'tea-2', name: 'Tea', category: 'Grocery',
        stockQuantity: 2, costPrice: 60, sellingPrice: 100,
      );
      expect(
        () => aggregatePurchaseOrderQuantities(
          items: [SupplierOrderItem(productName: 'Tea', requiredQuantity: 1, estimatedPrice: 50)],
          products: [tea, duplicateName],
        ),
        throwsStateError,
      );
    });

    test('purchase receipt rejects zero and negative quantities', () {
      final tea = Product(
        id: 'tea-id', name: 'Tea', category: 'Grocery',
        stockQuantity: 7, costPrice: 80, sellingPrice: 120,
      );
      expect(
        () => aggregatePurchaseOrderQuantities(
          items: [SupplierOrderItem(productName: 'Tea', requiredQuantity: 0, estimatedPrice: 50)],
          products: [tea],
        ),
        throwsStateError,
      );
      expect(
        () => aggregatePurchaseOrderQuantities(
          items: [SupplierOrderItem(productName: 'Tea', requiredQuantity: -2, estimatedPrice: 50)],
          products: [tea],
        ),
        throwsStateError,
      );
    });

    test('cloud child rows do not reuse device-local SQLite IDs', () {
      final cloudRow = prepareChildRowForCloud({
        'id': 47,
        'cloudId': 'stable-child-id',
        'billId': 'bill-1',
        'productId': 'tea-id',
        'quantity': 2,
      }, 'stable-child-id');

      expect(cloudRow.containsKey('id'), isFalse);
      expect(cloudRow['cloudId'], 'stable-child-id');
      expect(cloudRow['billId'], 'bill-1');
      expect(cloudRow['quantity'], 2);
    });

    test('pulled child rows get a stable cloud ID and a fresh local key', () {
      final localRow = prepareChildRowForLocal({
        'id': 47,
        'cloudId': 'old-cloud-id',
        'billId': 'bill-1',
        'quantity': 2,
        'updatedAt': 'server-timestamp',
      }, 'stable-cloud-id');

      expect(localRow.containsKey('id'), isFalse);
      expect(localRow['cloudId'], 'stable-cloud-id');
      expect(localRow.containsKey('updatedAt'), isFalse);
      expect(localRow['billId'], 'bill-1');
    });

    test('inventory rejects NaN and infinite prices', () {
      expect(
        () => validateProductValues(
          stockQuantity: 1,
          costPrice: double.nan,
          sellingPrice: 10,
          lowStockThreshold: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => validateProductValues(
          stockQuantity: 1,
          costPrice: 10,
          sellingPrice: double.infinity,
          lowStockThreshold: 1,
        ),
        throwsArgumentError,
      );
    });

    test('manual sales reject NaN and infinite prices', () {
      expect(
        () => validateManualSaleInput(
          productName: 'Tea',
          costPrice: double.nan,
          salePrice: 120,
          quantity: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => validateManualSaleInput(
          productName: 'Tea',
          costPrice: 80,
          salePrice: double.infinity,
          quantity: 1,
        ),
        throwsArgumentError,
      );
    });

    test('supplier balance cannot be negative conceptually', () {
      final supplier = Supplier(id: 's1', name: 'ABC', phone: '',
        totalStockReceivedValue: 1000, totalPaymentsMade: 400);
      expect(supplier.remainingBalance, 600);
    });
  });
}
