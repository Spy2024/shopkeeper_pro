import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/inventory_provider.dart';
import '../../models/product.dart';
import '../barcode_scanner_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);
  String _query = '';

  @override
  void initState() {
    super.initState();
    context.read<InventoryProvider>().load();
  }

  void _openProductForm({Product? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductFormSheet(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final products = inventory.search(_query);
    final alerts = inventory.lowOrOutOfStock;
    final expiryAlerts = inventory.expiredProducts.length + inventory.expiringSoonProducts.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search products', prefixIcon: Icon(Icons.search), isDense: true),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (expiryAlerts > 0)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_busy, color: Colors.orange.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${inventory.expiredProducts.length} expired • ${inventory.expiringSoonProducts.length} expiring within 30 days',
                      style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (alerts.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${alerts.length} item(s) low or out of stock',
                        style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('No products yet'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final p = products[i];
                      final statusColor = p.isOutOfStock
                          ? Colors.red
                          : p.isLowStock
                              ? Colors.orange
                              : Colors.green;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          onTap: () => _openProductForm(existing: p),
                          leading: CircleAvatar(
                            backgroundColor: statusColor.withValues(alpha: 0.15),
                            child: Icon(Icons.inventory_2, color: statusColor),
                          ),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            p.category,
                            'Stock: ${p.stockQuantity}',
                            'Margin: ${_currency.format(p.margin)}',
                            if (p.barcode != null && p.barcode!.isNotEmpty) 'Barcode: ${p.barcode}',
                            if (p.expiryDate != null)
                              p.isExpired
                                  ? 'EXPIRED: ${DateFormat('dd MMM yyyy').format(p.expiryDate!)}'
                                  : p.expiresWithin30Days
                                      ? 'Expires soon: ${DateFormat('dd MMM yyyy').format(p.expiryDate!)}'
                                      : 'Expiry: ${DateFormat('dd MMM yyyy').format(p.expiryDate!)}',
                          ].join(' • ')),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => context.read<InventoryProvider>().deleteProduct(p.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductFormSheet extends StatefulWidget {
  final Product? existing;
  const _ProductFormSheet({this.existing});

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  late final _categoryCtrl = TextEditingController(text: widget.existing?.category ?? '');
  late final _stockCtrl = TextEditingController(text: widget.existing?.stockQuantity.toString() ?? '');
  late final _cpCtrl = TextEditingController(text: widget.existing?.costPrice.toString() ?? '');
  late final _spCtrl = TextEditingController(text: widget.existing?.sellingPrice.toString() ?? '');
  late final _barcodeCtrl = TextEditingController(text: widget.existing?.barcode ?? '');
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _expiryDate = widget.existing?.expiryDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _stockCtrl.dispose();
    _cpCtrl.dispose();
    _spCtrl.dispose();
    _barcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (scanned != null && mounted) {
      setState(() => _barcodeCtrl.text = scanned);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isEdit ? 'Edit Product' : 'Add Product', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Product Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(labelText: 'Category'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _barcodeCtrl,
              decoration: InputDecoration(
                labelText: 'Barcode (optional)',
                prefixIcon: const Icon(Icons.qr_code_2),
                helperText: 'Use the camera or a handheld barcode scanner.',
                suffixIcon: IconButton(
                  tooltip: 'Scan barcode with camera',
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.document_scanner_outlined),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stock Quantity'),
              validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _expiryDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null && mounted) setState(() => _expiryDate = picked);
                    },
                    icon: const Icon(Icons.event),
                    label: Text(_expiryDate == null
                        ? 'Set expiry date'
                        : DateFormat('dd MMM yyyy').format(_expiryDate!)),
                  ),
                ),
                if (_expiryDate != null)
                  IconButton(
                    tooltip: 'Clear expiry date',
                    onPressed: () => setState(() => _expiryDate = null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cost Price'),
                    validator: (v) => (double.tryParse(v ?? '') == null) ? 'Invalid' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _spCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Selling Price'),
                    validator: (v) => (double.tryParse(v ?? '') == null) ? 'Invalid' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final inventory = context.read<InventoryProvider>();
                if (isEdit) {
                  await inventory.updateProduct(Product(
                    id: widget.existing!.id,
                    name: _nameCtrl.text.trim(),
                    category: _categoryCtrl.text.trim(),
                    stockQuantity: int.parse(_stockCtrl.text),
                    costPrice: double.parse(_cpCtrl.text),
                    sellingPrice: double.parse(_spCtrl.text),
                    lowStockThreshold: widget.existing!.lowStockThreshold,
                    barcode: _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
                    expiryDate: _expiryDate,
                  ));
                } else {
                  await inventory.addProduct(
                    name: _nameCtrl.text.trim(),
                    category: _categoryCtrl.text.trim(),
                    stockQuantity: int.parse(_stockCtrl.text),
                    costPrice: double.parse(_cpCtrl.text),
                    sellingPrice: double.parse(_spCtrl.text),
                    barcode: _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
                    expiryDate: _expiryDate,
                  );
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Product'),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }
}
