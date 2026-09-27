import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/supplier_provider.dart';
import '../../models/supplier.dart';
import '../../services/pdf_service.dart';

class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> with SingleTickerProviderStateMixin {
  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    context.read<SupplierProvider>().load();
  }

  void _addSupplierDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Supplier'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Supplier Name')),
          TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              context.read<SupplierProvider>().addSupplier(nameCtrl.text.trim(), phoneCtrl.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supplierProvider = context.watch<SupplierProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        bottom: TabBar(controller: _tabController, tabs: const [
          Tab(text: 'Ledger'),
          Tab(text: 'Orders'),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _addSupplierDialog();
          } else {
            _openNewOrderSheet(context, supplierProvider.suppliers);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0 ? 'Add Supplier' : 'New Order'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LedgerTab(suppliers: supplierProvider.suppliers, currency: _currency),
          _OrdersTab(orders: supplierProvider.orders, currency: _currency, suppliers: supplierProvider.suppliers),
        ],
      ),
    );
  }

  void _openNewOrderSheet(BuildContext context, List<Supplier> suppliers) {
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a supplier first')));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewOrderSheet(suppliers: suppliers),
    );
  }
}

class _LedgerTab extends StatelessWidget {
  final List<Supplier> suppliers;
  final NumberFormat currency;
  const _LedgerTab({required this.suppliers, required this.currency});

  @override
  Widget build(BuildContext context) {
    if (suppliers.isEmpty) return const Center(child: Text('No suppliers yet'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: suppliers.length,
      itemBuilder: (context, i) {
        final s = suppliers[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(s.phone, style: TextStyle(color: Colors.grey.shade600)),
                const Divider(),
                _statRow('Total Stock Received', currency.format(s.totalStockReceivedValue)),
                _statRow('Total Payments Made', currency.format(s.totalPaymentsMade)),
                _statRow('Remaining Balance', currency.format(s.remainingBalance), bold: true,
                    color: s.remainingBalance > 0 ? Colors.red : Colors.green),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _promptAmount(context, 'Record Stock Received', (v) =>
                            context.read<SupplierProvider>().recordStockReceived(s.id, v)),
                        child: const Text('Stock Received'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _promptAmount(context, 'Record Payment', (v) =>
                            context.read<SupplierProvider>().recordPayment(s.id, v)),
                        child: const Text('Record Payment'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statRow(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
          ],
        ),
      );

  void _promptAmount(BuildContext context, String title, void Function(double) onConfirm) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v > 0) onConfirm(v);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  final List<SupplierOrder> orders;
  final List<Supplier> suppliers;
  final NumberFormat currency;
  const _OrdersTab({required this.orders, required this.suppliers, required this.currency});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const Center(child: Text('No purchase orders yet'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (context, i) {
        final o = orders[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text(o.supplierName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${o.items.length} item(s) • ${currency.format(o.estimatedOrderTotal)}'),
            trailing: IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () async {
                final supplier = suppliers.firstWhere((s) => s.id == o.supplierId,
                    orElse: () => Supplier(id: o.supplierId, name: o.supplierName, phone: ''));
                final file = await PdfService.generatePurchaseOrder(
                  o.id,
                  supplier,
                  o.items
                      .map((it) => {
                            'productName': it.productName,
                            'requiredQuantity': it.requiredQuantity,
                            'estimatedPrice': it.estimatedPrice,
                          })
                      .toList(),
                  o.estimatedOrderTotal,
                );
                await Share.shareXFiles([XFile(file.path)],
                    text: 'Purchase order for ${o.supplierName}');
              },
            ),
          ),
        );
      },
    );
  }
}

class _NewOrderSheet extends StatefulWidget {
  final List<Supplier> suppliers;
  const _NewOrderSheet({required this.suppliers});

  @override
  State<_NewOrderSheet> createState() => _NewOrderSheetState();
}

class _NewOrderSheetState extends State<_NewOrderSheet> {
  Supplier? _selected;
  final List<SupplierOrderItem> _items = [];
  final _productCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = widget.suppliers.first;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('New Purchase Order', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<Supplier>(
            value: _selected,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: widget.suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
            onChanged: (v) => setState(() => _selected = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: _productCtrl, decoration: const InputDecoration(labelText: 'Product Name')),
          Row(children: [
            Expanded(child: TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Required Qty'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Estimated Price'))),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              final name = _productCtrl.text.trim();
              final qty = int.tryParse(_qtyCtrl.text) ?? 0;
              final price = double.tryParse(_priceCtrl.text) ?? 0;
              if (name.isEmpty || qty <= 0 || price <= 0) return;
              setState(() {
                _items.add(SupplierOrderItem(productName: name, requiredQuantity: qty, estimatedPrice: price));
                _productCtrl.clear();
                _qtyCtrl.clear();
                _priceCtrl.clear();
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Line Item'),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._items.map((i) => ListTile(
                  dense: true,
                  title: Text(i.productName),
                  subtitle: Text('${i.requiredQuantity} × ${i.estimatedPrice}'),
                )),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _items.isEmpty || _selected == null
                ? null
                : () async {
                    await context
                        .read<SupplierProvider>()
                        .createOrder(_selected!.id, _selected!.name, List.of(_items));
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Save Order'),
          ),
        ],
      ),
    );
  }
}
