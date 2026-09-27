import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/pos_provider.dart';

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
                    if (picked != null) setState(() => _dateFilter = picked);
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
                        trailing: Text(_currency.format(bill.grandTotal),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
