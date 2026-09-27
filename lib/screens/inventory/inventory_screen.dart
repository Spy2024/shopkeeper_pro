import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/inventory_provider.dart';
import '../../models/product.dart';

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
                            backgroundColor: statusColor.withOpacity(0.15),
                            child: Icon(Icons.inventory_2, color: statusColor),
                          ),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${p.category} • Stock: ${p.stockQuantity} • Margin: ${_currency.format(p.margin)}'),
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
              controller: _stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stock Quantity'),
              validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
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
                  ));
                } else {
                  await inventory.addProduct(
                    name: _nameCtrl.text.trim(),
                    category: _categoryCtrl.text.trim(),
                    stockQuantity: int.parse(_stockCtrl.text),
                    costPrice: double.parse(_cpCtrl.text),
                    sellingPrice: double.parse(_spCtrl.text),
                  );
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Product'),
            ),
          ],
        ),
      ),
    );
  }
}
