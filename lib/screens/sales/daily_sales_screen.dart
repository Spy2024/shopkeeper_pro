import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/sales_provider.dart';

class DailySalesScreen extends StatefulWidget {
  const DailySalesScreen({super.key});

  @override
  State<DailySalesScreen> createState() => _DailySalesScreenState();
}

class _DailySalesScreenState extends State<DailySalesScreen> {
  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    context.read<SalesProvider>().load();
  }

  void _openAddRowSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddSaleRowSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    final today = sales.salesForDay(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Sales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddRowSheet,
        icon: const Icon(Icons.add),
        label: const Text('Add Sale'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric('Today\'s Revenue', _currency.format(sales.todayRevenue)),
                _metric('Today\'s Margin', _currency.format(sales.todayMargin)),
              ],
            ),
          ),
          Expanded(
            child: today.isEmpty
                ? const Center(child: Text('No sales logged today'))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Product Name')),
                        DataColumn(label: Text('Cost Price'), numeric: true),
                        DataColumn(label: Text('Sale Price'), numeric: true),
                        DataColumn(label: Text('Margin'), numeric: true),
                      ],
                      rows: today
                          .map((s) => DataRow(cells: [
                                DataCell(Text(s.productName)),
                                DataCell(Text(_currency.format(s.costPrice))),
                                DataCell(Text(_currency.format(s.salePrice))),
                                DataCell(Text(
                                  _currency.format(s.margin),
                                  style: TextStyle(
                                    color: s.margin >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )),
                              ]))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      );
}

class _AddSaleRowSheet extends StatefulWidget {
  const _AddSaleRowSheet();

  @override
  State<_AddSaleRowSheet> createState() => _AddSaleRowSheetState();
}

class _AddSaleRowSheetState extends State<_AddSaleRowSheet> {
  final _nameCtrl = TextEditingController();
  final _cpCtrl = TextEditingController();
  final _spCtrl = TextEditingController();

  double get _margin => (double.tryParse(_spCtrl.text) ?? 0) - (double.tryParse(_cpCtrl.text) ?? 0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Log a Sale', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Product Name')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _cpCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cost Price'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _spCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sale Price'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Margin: ${_margin.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: _margin >= 0 ? Colors.green : Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final name = _nameCtrl.text.trim();
              final cp = double.tryParse(_cpCtrl.text);
              final sp = double.tryParse(_spCtrl.text);
              if (name.isEmpty || cp == null || sp == null) return;
              await context.read<SalesProvider>().addRow(productName: name, costPrice: cp, salePrice: sp);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save Sale'),
          ),
        ],
      ),
    );
  }
}
