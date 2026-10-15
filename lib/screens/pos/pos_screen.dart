import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../providers/pos_provider.dart';
import '../../models/bill.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/db_service.dart';
import '../../services/branch_accounting_service.dart';
import '../../services/mobile_shop_service.dart';
import 'bill_history_screen.dart';
import '../barcode_scanner_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Map<String, Object?>> _activeBranches = [];
  String? _selectedBranchId;
  bool _loadingBranches = true;

  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final db = await DBService.instance.database;
      final rows = await db.query(
        'branches',
        where: 'isActive = ?',
        whereArgs: [1],
        orderBy: 'isMain DESC, name COLLATE NOCASE',
      );
      if (!mounted) return;
      setState(() {
        _activeBranches = rows;
        _selectedBranchId = rows.isEmpty ? null : rows.first['id'] as String;
        _loadingBranches = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingBranches = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load branches: $e')),
      );
    }
  }

  void _openAddItemSheet() {
    final inventory = context.read<InventoryProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddItemSheet(inventory: inventory, currency: _currency),
    );
  }

  void _openMobilePhoneSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.72,
          child: FutureBuilder(
            future: MobileShopService.instance.listDevices(status: 'in_stock'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return Center(child: Text('Could not load phones: \${snapshot.error}'));
              final devices = snapshot.data ?? const [];
              if (devices.isEmpty) return const Center(child: Text('No sale-ready phones. Check used-phone inspection status.'));
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Select exact IMEI phone', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final device in devices)
                    Card(
                      child: ListTile(
                        title: Text('\${device.brand} \${device.model}'),
                        subtitle: Text('IMEI: \${device.imei1 ?? '—'}\${device.imei2 == null ? '' : '\nIMEI 2: \${device.imei2}'}\nStatus: \${device.status}'),
                        isThreeLine: true,
                        trailing: Text(_currency.format(device.sellingPrice)),
                        onTap: () {
                          try {
                            context.read<PosProvider>().addMobileDevice(device);
                            Navigator.pop(sheetContext);
                          } catch (error) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('\$error')));
                          }
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final isMobileShop = context.watch<ShopProvider>().shop?.businessType == 'mobile_electronics';

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Bill'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Bill History',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const BillHistoryScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingBranches)
            const LinearProgressIndicator(minHeight: 2)
          else if (_activeBranches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedBranchId,
                decoration: const InputDecoration(
                  labelText: 'Selling branch',
                  prefixIcon: Icon(Icons.store_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _activeBranches.map((branch) {
                  final id = branch['id'] as String;
                  final name = (branch['name'] as String?) ?? id;
                  final code = (branch['code'] as String?) ?? '';
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(code.isEmpty ? name : '$name ($code)'),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedBranchId = value),
              ),
            ),
          Expanded(
            child: pos.cart.isEmpty
                ? const _EmptyCart()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: pos.cart.length,
                    itemBuilder: (context, i) {
                      final item = pos.cart[i];
                      return Card(
                        child: ListTile(
                          title: Text(item.productName),
                          subtitle: Text('${item.quantity} × ${_currency.format(item.unitPrice)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_currency.format(item.lineTotal),
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => pos.removeItem(i),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _BillSummaryPanel(pos: pos, currency: _currency, onAddItem: _openAddItemSheet, onAddMobilePhone: _openMobilePhoneSheet, isMobileShop: isMobileShop, branchId: _selectedBranchId),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('No items yet — tap "Add Item" below', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _BillSummaryPanel extends StatelessWidget {
  final PosProvider pos;
  final NumberFormat currency;
  final VoidCallback onAddItem;
  final VoidCallback onAddMobilePhone;
  final bool isMobileShop;
  final String? branchId;

  const _BillSummaryPanel({required this.pos, required this.currency, required this.onAddItem, required this.onAddMobilePhone, required this.isMobileShop, required this.branchId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: onAddItem,
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            if (isMobileShop) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onAddMobilePhone,
                icon: const Icon(Icons.phonelink_setup),
                label: const Text('Add Phone by IMEI'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
            const SizedBox(height: 12),
            _totalsRow('Subtotal', currency.format(pos.subtotal)),
            if (pos.discount > 0) _totalsRow('Discount', '-${currency.format(pos.discount)}'),
            if (pos.taxPercent > 0)
              _totalsRow('Tax (${pos.taxPercent.toStringAsFixed(1)}%)', currency.format(pos.taxAmount)),
            _totalsRow('Grand Total', currency.format(pos.grandTotal), bold: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: pos.cart.isEmpty
                        ? null
                        : () => _showAdjustmentsDialog(context, pos),
                    icon: const Icon(Icons.percent),
                    label: const Text('Discount/Tax'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: pos.cart.isEmpty ? null : () => _checkoutAndShare(context, pos, branchId),
                    icon: const Icon(Icons.print),
                    label: const Text('Checkout & Print'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null),
            Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16) : null),
          ],
        ),
      );

  Future<void> _showAdjustmentsDialog(BuildContext context, PosProvider pos) async {
    final discountCtrl = TextEditingController(text: pos.discount == 0 ? '' : pos.discount.toString());
    final taxCtrl = TextEditingController(text: pos.taxPercent == 0 ? '' : pos.taxPercent.toString());
    final nameCtrl = TextEditingController(text: pos.customerName ?? '');
    final addressCtrl = TextEditingController(text: pos.customerAddress ?? '');
    final phoneCtrl = TextEditingController(text: pos.customerPhone ?? '');
    final emailCtrl = TextEditingController(text: pos.customerEmail ?? '');
    try {
      await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discount, Tax & Customer'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Customer Name (optional)'),
            ),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Customer Address (optional)'), maxLines: 2),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Customer Phone (optional)')),
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Customer Email (optional)')),
            TextField(
              controller: discountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Discount (amount)'),
            ),
            TextField(
              controller: taxCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Tax (%)'),
            ),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final discount = double.tryParse(discountCtrl.text.trim()) ?? 0;
              final tax = double.tryParse(taxCtrl.text.trim()) ?? 0;
              if (!discount.isFinite || discount < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Discount must be a valid non-negative amount.')),
                );
                return;
              }
              if (!tax.isFinite || tax < 0 || tax > 100) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tax must be between 0 and 100%.')),
                );
                return;
              }
              final email = emailCtrl.text.trim();
              if (email.isNotEmpty &&
                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid customer email.')),
                );
                return;
              }
              pos.setCustomerDetails(
                name: nameCtrl.text,
                address: addressCtrl.text,
                phone: phoneCtrl.text,
                email: email,
              );
              pos.setDiscount(discount);
              pos.setTax(tax);
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
      );
    } finally {
      discountCtrl.dispose();
      taxCtrl.dispose();
      nameCtrl.dispose();
      addressCtrl.dispose(); phoneCtrl.dispose(); emailCtrl.dispose();
    }
  }

  Future<_CheckoutPayment?> _showPaymentDialog(BuildContext context, double total) async {
    final db = await DBService.instance.database;
    final customers = await db.query('customers', columns: ['id', 'name'], orderBy: 'name COLLATE NOCASE');
    if (!context.mounted) return null;
    String firstMethod = 'cash';
    String secondMethod = 'credit';
    String? customerId;
    final firstAmount = TextEditingController(text: total.toStringAsFixed(2));
    final secondAmount = TextEditingController(text: '0.00');
    try {
      return await showDialog<_CheckoutPayment>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Payment & Udhaar'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Bill total: ${NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2).format(total)}'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: firstMethod,
                    decoration: const InputDecoration(labelText: 'Payment 1'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank')),
                      DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                      DropdownMenuItem(value: 'credit', child: Text('Udhaar / Credit')),
                    ],
                    onChanged: (value) => setDialogState(() => firstMethod = value ?? 'cash'),
                  ),
                  TextField(controller: firstAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount 1')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: secondMethod,
                    decoration: const InputDecoration(labelText: 'Payment 2 (optional)'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank')),
                      DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                      DropdownMenuItem(value: 'credit', child: Text('Udhaar / Credit')),
                    ],
                    onChanged: (value) => setDialogState(() => secondMethod = value ?? 'credit'),
                  ),
                  TextField(controller: secondAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount 2'),
                    onChanged: (_) => setDialogState(() {})),
                  if (firstMethod == 'credit' || (secondMethod == 'credit' && (double.tryParse(secondAmount.text.trim()) ?? 0) > 0))
                    DropdownButtonFormField<String>(
                      initialValue: customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Customer required for udhaar'),
                      items: customers.map((customer) => DropdownMenuItem<String>(
                        value: customer['id'] as String,
                        child: Text((customer['name'] as String?) ?? 'Unnamed customer'),
                      )).toList(),
                      onChanged: (value) => setDialogState(() => customerId = value),
                    ),
                  const SizedBox(height: 8),
                  Text('Allocated: ${NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2).format((double.tryParse(firstAmount.text) ?? 0) + (double.tryParse(secondAmount.text) ?? 0))}'),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final a = double.tryParse(firstAmount.text.trim());
                  final b = double.tryParse(secondAmount.text.trim());
                  if (a == null || b == null || !a.isFinite || !b.isFinite || a < 0 || b < 0 || (a + b - total).abs() > 0.005) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment amounts must add up to the bill total.')));
                    return;
                  }
                  if (((firstMethod == 'credit' && a > 0) || (secondMethod == 'credit' && b > 0)) && customerId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a customer for udhaar.')));
                    return;
                  }
                  final allocations = <PaymentAllocationInput>[
                    PaymentAllocationInput(method: firstMethod, amount: a),
                    if (b > 0) PaymentAllocationInput(method: secondMethod, amount: b),
                  ];
                  Navigator.pop(dialogContext, _CheckoutPayment(customerId: customerId, allocations: allocations));
                },
                child: const Text('Confirm Payment'),
              ),
            ],
          ),
        ),
      );
    } finally {
      firstAmount.dispose();
      secondAmount.dispose();
    }
  }

  Future<void> _checkoutAndShare(BuildContext context, PosProvider pos, String? branchId) async {
    final inventory = context.read<InventoryProvider>();
    final shop = context.read<ShopProvider>().shop;
    late final Bill bill;
    try {
      final payment = await _showPaymentDialog(context, pos.grandTotal);
      if (payment == null || !context.mounted) return;
      bill = await pos.checkout(inventory, branchId: branchId, customerId: payment.customerId, paymentAllocations: payment.allocations);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout failed; no bill was confirmed: $e')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    try {
      final file = await PdfService.generateInvoice(bill, shop);
      if (!context.mounted) return;

      // Checkout clears the cart and notifies listeners. Let Flutter finish
      // rebuilding the POS tree before opening the native print UI.
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;

      final pdfBytes = await file.readAsBytes();
      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: 'Shopkeeper-Pro-Invoice',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bill saved successfully, but printing failed: $e')),
        );
      }
    }
  }
}

class _AddItemSheet extends StatefulWidget {
  final InventoryProvider inventory;
  final NumberFormat currency;
  const _AddItemSheet({required this.inventory, required this.currency});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  String? _selectedProductId;

  void _selectProduct(String name, double price, String productId) {
    _nameCtrl.text = name;
    _priceCtrl.text = price.toString();
    _selectedProductId = productId;
    setState(() {});
  }

  Future<void> _scanBarcode() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (scanned == null || !mounted) return;

    final normalized = scanned.trim().toLowerCase();
    final exactMatches = widget.inventory.products
        .where((product) => product.barcode?.trim().toLowerCase() == normalized)
        .toList(growable: false);
    if (exactMatches.length == 1) {
      final product = exactMatches.single;
      _selectProduct(product.name, product.sellingPrice, product.id);
      return;
    }

    _nameCtrl.text = scanned;
    _selectedProductId = null;
    setState(() {});
    if (exactMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No product has this barcode. Add it in Inventory first.')),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.inventory.search(_nameCtrl.text);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add Item', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'Product name or barcode',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Scan barcode with camera',
                onPressed: _scanBarcode,
                icon: const Icon(Icons.document_scanner_outlined),
              ),
            ),
            onChanged: (value) {
              final selected = widget.inventory.findById(_selectedProductId ?? '');
              if (selected != null && value.trim() != selected.name) {
                _selectedProductId = null;
              }
              setState(() {});
            },
          ),
          if (_nameCtrl.text.isNotEmpty && results.isNotEmpty)
            SizedBox(
              height: 140,
              child: ListView(
                children: results
                    .map((p) => ListTile(
                          dense: true,
                          title: Text(p.name),
                          subtitle: Text('Stock: ${p.stockQuantity} • ${widget.currency.format(p.sellingPrice)}'),
                          onTap: () => _selectProduct(p.name, p.sellingPrice, p.id),
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Unit Price'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final name = _nameCtrl.text.trim();
              final qty = int.tryParse(_qtyCtrl.text) ?? 0;
              final price = double.tryParse(_priceCtrl.text) ?? 0;
              if (name.isEmpty || qty <= 0 || price <= 0) return;
              final selected = widget.inventory.products.where((p) => p.id == _selectedProductId).toList();
              context.read<PosProvider>().addItem(name, qty, price, productId: selected.isEmpty ? null : selected.first.id);
              Navigator.pop(context);
            },
            child: const Text('Add to Bill'),
          ),
        ],
      ),
    );
  }
}

class _CheckoutPayment {
  final String? customerId;
  final List<PaymentAllocationInput> allocations;
  const _CheckoutPayment({required this.customerId, required this.allocations});
}
