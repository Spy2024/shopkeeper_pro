import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../models/bill.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/pdf_service.dart';

class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);
  final _customerCtrl = TextEditingController();
  DateTime? _dateFilter;

  @override
  void initState() {
    super.initState();
    context.read<PosProvider>().loadHistory();
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    super.dispose();
  }

  Future<void> _reprintBill(Bill bill) async {
    try {
      final file = await PdfService.generateInvoice(
        bill,
        context.read<ShopProvider>().shop,
      );
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) => file.readAsBytes());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reprint bill: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _returnBill(Bill bill) async {
    if (bill.items.isEmpty) return;
    final reasonController = TextEditingController();
    BillItem selectedItem = bill.items.first;
    final quantityController = TextEditingController(text: '1');
    String? dialogError;
    double? refundAmount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Return items'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Bill ${bill.id.length > 8 ? bill.id.substring(0, 8).toUpperCase() : bill.id.toUpperCase()}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<BillItem>(
                  initialValue: selectedItem,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: bill.items.map((item) => DropdownMenuItem(
                    value: item,
                    child: Text('${item.productName} (sold ${item.quantity})', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (item) {
                    if (item == null) return;
                    setDialogState(() {
                      selectedItem = item;
                      quantityController.text = '1';
                      dialogError = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity to return'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(labelText: 'Reason for return'),
                  maxLines: 2,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final quantity = int.tryParse(quantityController.text);
                if (quantity == null || quantity <= 0) {
                  setDialogState(() => dialogError = 'Enter a valid return quantity.');
                  return;
                }
                if (reasonController.text.trim().isEmpty) {
                  setDialogState(() => dialogError = 'Enter a reason for the return.');
                  return;
                }
                try {
                  refundAmount = await context.read<PosProvider>().returnItem(
                    bill: bill,
                    item: selectedItem,
                    quantity: quantity,
                    reason: reasonController.text,
                    inventory: context.read<InventoryProvider>(),
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, true);
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() => dialogError = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Confirm return'),
            ),
          ],
        ),
      ),
    );

    reasonController.dispose();
    quantityController.dispose();
    if (confirmed != true || !mounted) return;

    await Future.wait([
      context.read<PosProvider>().loadHistory(),
      context.read<InventoryProvider>().load(),
      context.read<SalesProvider>().load(),
    ]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Return recorded. Refund: ${_currency.format(refundAmount ?? 0)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final results = pos.filterHistory(date: _dateFilter, customer: _customerCtrl.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Bill History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customerCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search customer name',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  icon: Icon(_dateFilter == null ? Icons.calendar_today_outlined : Icons.event_busy),
                  tooltip: _dateFilter == null ? 'Filter by date' : 'Clear date filter',
                  onPressed: () async {
                    if (_dateFilter != null) {
                      setState(() => _dateFilter = null);
                      return;
                    }
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDate: DateTime.now(),
                    );
                    if (picked != null && mounted) setState(() => _dateFilter = picked);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('No matching bills'))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final bill = results[i];
                      return ListTile(
                        title: Text(bill.customerName?.isNotEmpty == true ? bill.customerName! : 'Walk-in Customer'),
                        subtitle: Text(DateFormat('dd MMM yyyy, hh:mm a').format(bill.date)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_currency.format(bill.grandTotal),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            PopupMenuButton<String>(
                              tooltip: 'Bill actions',
                              onSelected: (action) {
                                if (action == 'reprint') _reprintBill(bill);
                                if (action == 'return') _returnBill(bill);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'reprint',
                                  child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Reprint bill')),
                                ),
                                PopupMenuItem(
                                  value: 'return',
                                  child: ListTile(leading: Icon(Icons.assignment_return_outlined), title: Text('Return items')),
                                ),
                              ],
                            ),
                          ],
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
