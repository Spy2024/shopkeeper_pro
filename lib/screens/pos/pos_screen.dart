import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../providers/pos_provider.dart';
import '../../models/bill.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/pdf_service.dart';
import 'bill_history_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

  void _openAddItemSheet() {
    final inventory = context.read<InventoryProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddItemSheet(inventory: inventory, currency: _currency),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();

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
          _BillSummaryPanel(pos: pos, currency: _currency, onAddItem: _openAddItemSheet),
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

  const _BillSummaryPanel({required this.pos, required this.currency, required this.onAddItem});

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
                    onPressed: pos.cart.isEmpty ? null : () => _checkoutAndShare(context, pos),
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
    try {
      await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discount, Tax & Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Customer Name (optional)'),
            ),
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
        ),
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
              pos.setCustomerName(nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim());
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
    }
  }

  Future<void> _checkoutAndShare(BuildContext context, PosProvider pos) async {
    final inventory = context.read<InventoryProvider>();
    final shop = context.read<ShopProvider>().shop;
    late final Bill bill;
    try {
      bill = await pos.checkout(inventory);
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
      await Printing.layoutPdf(onLayout: (_) => file.readAsBytes());
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
            decoration: const InputDecoration(labelText: 'Product Name', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
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
