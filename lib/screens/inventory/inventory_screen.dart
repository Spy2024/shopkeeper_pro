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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: _InventoryMetric(
                    label: 'Products',
                    value: inventory.products.length.toString(),
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFF0F9D91),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InventoryMetric(
                    label: 'Low stock',
                    value: inventory.lowOrOutOfStock.length.toString(),
                    icon: Icons.warning_amber_rounded,
                    color: const Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InventoryMetric(
                    label: 'Units',
                    value: inventory.products.fold<int>(0, (sum, product) => sum + product.stockQuantity).toString(),
                    icon: Icons.stacked_bar_chart,
                    color: const Color(0xFF315A9B),
                  ),
                ),
              ],
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
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _openProductForm(existing: p),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(Icons.inventory_2_rounded, color: statusColor, size: 25),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(p.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 4),
                                          Text(p.category,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              p.isOutOfStock ? 'OUT OF STOCK' : p.isLowStock ? 'LOW STOCK' : 'IN STOCK',
                                              style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Product actions',
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          _openProductForm(existing: p);
                                        } else if (value == 'delete') {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (dialogContext) => AlertDialog(
                                              title: const Text('Delete product?'),
                                              content: Text('Remove "${p.name}" from inventory?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dialogContext, false),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  onPressed: () => Navigator.pop(dialogContext, true),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true && context.mounted) {
                                            await context.read<InventoryProvider>().deleteProduct(p.id);
                                          }
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), dense: true)),
                                        PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'), dense: true)),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ProductValue(
                                        label: 'SELLING PRICE',
                                        value: _currency.format(p.sellingPrice),
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _ProductValue(
                                        label: 'STOCK',
                                        value: p.stockQuantity.toString(),
                                        color: statusColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _ProductValue(
                                        label: 'MARGIN / UNIT',
                                        value: _currency.format(p.margin),
                                        color: const Color(0xFF0F9D91),
                                      ),
                                    ),
                                  ],
                                ),
                                if ((p.barcode != null && p.barcode!.isNotEmpty) || p.expiryDate != null) ...[
                                  const SizedBox(height: 10),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    children: [
                                      if (p.barcode != null && p.barcode!.isNotEmpty)
                                        _ProductMeta(icon: Icons.qr_code_2, text: p.barcode!),
                                      if (p.expiryDate != null)
                                        _ProductMeta(
                                          icon: Icons.event_outlined,
                                          text: p.isExpired
                                              ? 'EXPIRED: ${DateFormat('dd MMM yyyy').format(p.expiryDate!)}'
                                              : p.expiresWithin30Days
                                                  ? 'Expires soon: ${DateFormat('dd MMM yyyy').format(p.expiryDate!)}'
                                                  : 'Expiry: ${DateFormat('dd MMM yyyy').format(p.expiryDate!)}',
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
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

class _InventoryMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InventoryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _ProductValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ProductValue({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.3)),
            const SizedBox(height: 5),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );
}

class _ProductMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ProductMeta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      );
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
  bool _saving = false;

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
              onPressed: _saving
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      setState(() => _saving = true);
                      try {
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
                            barcode: _barcodeCtrl.text.trim().isEmpty
                                ? null
                                : _barcodeCtrl.text.trim(),
                            expiryDate: _expiryDate,
                          ));
                        } else {
                          await inventory.addProduct(
                            name: _nameCtrl.text.trim(),
                            category: _categoryCtrl.text.trim(),
                            stockQuantity: int.parse(_stockCtrl.text),
                            costPrice: double.parse(_cpCtrl.text),
                            sellingPrice: double.parse(_spCtrl.text),
                            barcode: _barcodeCtrl.text.trim().isEmpty
                                ? null
                                : _barcodeCtrl.text.trim(),
                            expiryDate: _expiryDate,
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Could not save product: ${e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '')}",
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save Changes' : 'Add Product'),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }
}
