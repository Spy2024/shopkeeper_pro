import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/business_branch.dart';
import '../../models/product.dart';
import '../../providers/branch_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/shop_provider.dart';
import '../../utils/theme.dart';
import '../mobile_shop/mobile_shop_screen.dart';
import '../../services/branch_accounting_service.dart';
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

  Future<void> _openBranchStockDialog() async {
    final branchesProvider = context.read<BranchProvider>();
    final inventory = context.read<InventoryProvider>();
    try {
      await branchesProvider.load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load branches: $e')),
      );
      return;
    }
    if (!mounted) return;
    final branches = branchesProvider.branches.where((branch) => branch.isActive).toList();
    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create or activate a branch before allocating stock.')),
      );
      return;
    }
    if (inventory.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a product before allocating branch stock.')),
      );
      return;
    }
    await showDialog<bool>(
      context: context,
      builder: (_) => _BranchStockDialog(
        branches: branches,
        products: inventory.products,
      ),
    );
  }

  Future<void> _openStockTransferDialog() async {
    final branchesProvider = context.read<BranchProvider>();
    final inventory = context.read<InventoryProvider>();
    try {
      await branchesProvider.load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load branches: $e')),
      );
      return;
    }
    if (!mounted) return;
    final branches = branchesProvider.branches.where((branch) => branch.isActive).toList();
    if (branches.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create or activate at least two branches to transfer stock.')),
      );
      return;
    }
    if (inventory.products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a product before transferring stock.')),
      );
      return;
    }
    await showDialog<bool>(
      context: context,
      builder: (_) => _StockTransferDialog(
        branches: branches,
        products: inventory.products,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final isMobileShop = context.watch<ShopProvider>().shop?.businessType == 'mobile_electronics';
    final products = inventory.search(_query);
    final alerts = inventory.lowOrOutOfStock;
    final expiryAlerts = inventory.expiredProducts.length + inventory.expiringSoonProducts.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          if (isMobileShop)
            IconButton(
              tooltip: 'Mobile devices and repair jobs',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MobileShopScreen()),
              ),
              icon: const Icon(Icons.phone_android),
            ),
          IconButton(
            tooltip: 'Manage branch stock',
            onPressed: _openBranchStockDialog,
            icon: const Icon(Icons.store_mall_directory_outlined),
          ),
          IconButton(
            tooltip: 'Transfer stock between branches',
            onPressed: _openStockTransferDialog,
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
      ),
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
                    color: AppTheme.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InventoryMetric(
                    label: 'Low stock',
                    value: inventory.lowOrOutOfStock.length.toString(),
                    icon: Icons.warning_amber_rounded,
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InventoryMetric(
                    label: 'Units',
                    value: inventory.products.fold<int>(0, (sum, product) => sum + product.stockQuantity).toString(),
                    icon: Icons.stacked_bar_chart,
                    color: AppTheme.ink,
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
                                        color: AppTheme.teal,
                                      ),
                                    ),
                                  ],
                                ),
                                if ((p.barcode != null && p.barcode!.isNotEmpty) || p.expiryDate != null || p.businessAttributes.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    children: [
                                      if (p.barcode != null && p.barcode!.isNotEmpty)
                                        _ProductMeta(icon: Icons.qr_code_2, text: p.barcode!),
                                      ...p.businessAttributes.entries.where((entry) => entry.value.trim().isNotEmpty).map((entry) => _ProductMeta(icon: Icons.tune, text: '${entry.key}: ${entry.value}')),
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

class _StockTransferDialog extends StatefulWidget {
  final List<BusinessBranch> branches;
  final List<Product> products;

  const _StockTransferDialog({required this.branches, required this.products});

  @override
  State<_StockTransferDialog> createState() => _StockTransferDialogState();
}

class _StockTransferDialogState extends State<_StockTransferDialog> {
  final _quantityController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  late String _fromBranchId;
  late String _toBranchId;
  late String _productId;
  int _available = 0;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fromBranchId = widget.branches.first.id;
    _toBranchId = widget.branches.firstWhere((b) => b.id != _fromBranchId).id;
    _productId = widget.products.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSourceStock());
  }

  Future<void> _loadSourceStock() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final available = await BranchAccountingService.instance.branchStock(_fromBranchId, _productId);
      if (!mounted) return;
      setState(() {
        _available = available;
        _quantityController.text = available > 0 ? '1' : '0';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'Enter a whole-number quantity greater than zero.');
      return;
    }
    if (quantity > _available) {
      setState(() => _error = 'Only $_available unit(s) are available in the source branch.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await BranchAccountingService.instance.transferStock(
        fromBranchId: _fromBranchId,
        toBranchId: _toBranchId,
        productId: _productId,
        quantity: quantity,
        note: _noteController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Transfer Stock'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _fromBranchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'From branch'),
              items: widget.branches.map((b) => DropdownMenuItem<String>(
                value: b.id,
                child: Text('${b.name} (${b.code})'),
              )).toList(),
              onChanged: _saving ? null : (value) {
                if (value == null) return;
                setState(() {
                  _fromBranchId = value;
                  if (_toBranchId == value) {
                    _toBranchId = widget.branches.firstWhere((b) => b.id != value).id;
                  }
                });
                _loadSourceStock();
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _toBranchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'To branch'),
              items: widget.branches.where((b) => b.id != _fromBranchId).map((b) => DropdownMenuItem<String>(
                value: b.id,
                child: Text('${b.name} (${b.code})'),
              )).toList(),
              onChanged: _saving ? null : (value) {
                if (value != null) setState(() => _toBranchId = value);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _productId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Product'),
              items: widget.products.map((p) => DropdownMenuItem<String>(
                value: p.id,
                child: Text('${p.name} • total ${p.stockQuantity}'),
              )).toList(),
              onChanged: _saving ? null : (value) {
                if (value == null) return;
                setState(() => _productId = value);
                _loadSourceStock();
              },
            ),
            const SizedBox(height: 8),
            Text('Available in source: $_available units'),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity to transfer',
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Transfer note (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Transfer'),
        ),
      ],
    );
  }
}

class _BranchStockDialog extends StatefulWidget {
  final List<BusinessBranch> branches;
  final List<Product> products;

  const _BranchStockDialog({
    required this.branches,
    required this.products,
  });

  @override
  State<_BranchStockDialog> createState() => _BranchStockDialogState();
}

class _BranchStockDialogState extends State<_BranchStockDialog> {
  final _quantityController = TextEditingController(text: '0');
  late String _branchId;
  late String _productId;
  bool _loadingStock = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = widget.branches.first.id;
    _productId = widget.products.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStock());
  }

  Future<void> _loadStock() async {
    setState(() {
      _loadingStock = true;
      _error = null;
    });
    try {
      final quantity = await BranchAccountingService.instance.branchStock(
        _branchId,
        _productId,
      );
      if (!mounted) return;
      _quantityController.text = quantity.toString();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  Future<void> _save() async {
    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity < 0) {
      setState(() => _error = 'Enter a whole-number quantity of zero or more.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await BranchAccountingService.instance.setBranchStock(
        branchId: _branchId,
        productId: _productId,
        quantity: quantity,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.products.firstWhere((item) => item.id == _productId);
    return AlertDialog(
      title: const Text('Allocate Branch Stock'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _branchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Branch'),
              items: widget.branches.map((branch) => DropdownMenuItem<String>(
                value: branch.id,
                child: Text('${branch.name} (${branch.code})'),
              )).toList(),
              onChanged: _saving ? null : (value) {
                if (value == null) return;
                setState(() => _branchId = value);
                _loadStock();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _productId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Product'),
              items: widget.products.map((item) => DropdownMenuItem<String>(
                value: item.id,
                child: Text('${item.name} • total ${item.stockQuantity}'),
              )).toList(),
              onChanged: _saving ? null : (value) {
                if (value == null) return;
                setState(() => _productId = value);
                _loadStock();
              },
            ),
            const SizedBox(height: 12),
            Text('Total inventory: ${product.stockQuantity} units'),
            const SizedBox(height: 8),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantity allocated to this branch',
                helperText: 'Cannot exceed total stock after other branch allocations.',
                suffixIcon: _loadingStock
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _loadingStock ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save Allocation'),
        ),
      ],
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

List<String> _inventoryFieldsForBusiness(String businessType) {
  final type = businessType.toLowerCase();
  if (type.contains('mobile')) return ['Brand', 'Model', 'Storage / Variant', 'Colour', 'IMEI / Serial', 'Condition', 'Warranty'];
  if (type.contains('restaurant') || type.contains('food')) return ['Unit (kg/litre/pcs)', 'Ingredient or Menu Item', 'Recipe / Menu Group', 'Supplier Batch', 'Wastage %'];
  if (type.contains('snooker')) return ['Item Type (drink/snack/other)', 'Unit', 'Brand', 'Expiry / Batch'];
  if (type.contains('cloth') || type.contains('garment') || type.contains('fashion')) return ['Brand', 'Size', 'Colour', 'Fabric / Material', 'Design / SKU'];
  if (type.contains('carpet')) return ['Material', 'Length', 'Width', 'Colour / Design', 'Unit'];
  if (type.contains('furniture')) return ['Material', 'Dimensions', 'Colour / Finish', 'Model / SKU', 'Warranty'];
  if (type.contains('spare') || type.contains('auto') || type.contains('vehicle')) return ['Part Number', 'Compatible Make / Model', 'Year Range', 'Brand', 'Condition'];
  if (type.contains('cosmetic') || type.contains('pharmacy') || type.contains('medical')) return ['Brand', 'Unit / Pack Size', 'Batch Number', 'Manufacturer', 'Expiry / Best Before'];
  if (type.contains('transport') || type.contains('cargo')) return ['Item / Service Type', 'Unit', 'Route / Compatibility', 'Reference Code'];
  if (type.contains('agriculture')) return ['Brand', 'Unit / Pack Size', 'Batch Number', 'Expiry / Season'];
  if (type.contains('construction')) return ['Material Grade', 'Unit (bag/ft/kg/pcs)', 'Size / Dimensions', 'Brand'];
  return ['Brand', 'Unit / Pack Size', 'SKU / Model', 'Supplier Batch'];
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
  late final String _businessType;
  late final List<String> _attributeFields;
  late final Map<String, TextEditingController> _attributeCtrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _expiryDate = widget.existing?.expiryDate;
    _businessType = context.read<ShopProvider>().shop?.businessType ?? 'general_retail';
    _attributeFields = _inventoryFieldsForBusiness(_businessType);
    _attributeCtrls = {
      for (final field in _attributeFields)
        field: TextEditingController(text: widget.existing?.businessAttributes[field] ?? ''),
    };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _stockCtrl.dispose();
    _cpCtrl.dispose();
    _spCtrl.dispose();
    _barcodeCtrl.dispose();
    for (final controller in _attributeCtrls.values) { controller.dispose(); }
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text('$_businessType inventory details', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            ..._attributeFields.map((field) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextFormField(
                controller: _attributeCtrls[field],
                decoration: InputDecoration(labelText: field, isDense: true),
                textCapitalization: TextCapitalization.sentences,
              ),
            )),
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
                            businessAttributes: {for (final entry in _attributeCtrls.entries) if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim()},
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
                            businessAttributes: {for (final entry in _attributeCtrls.entries) if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim()},
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