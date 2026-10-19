import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/shop_provider.dart';
import '../../services/pdf_service.dart';
import '../../providers/finance_provider.dart';
import '../../providers/sales_provider.dart';
import '../../utils/theme.dart';

class FinancialDashboardScreen extends StatefulWidget {
  const FinancialDashboardScreen({super.key});

  @override
  State<FinancialDashboardScreen> createState() => _FinancialDashboardScreenState();
}

class _FinancialDashboardScreenState extends State<FinancialDashboardScreen> {
  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    context.read<FinanceProvider>().load();
    context.read<SalesProvider>().load();
  }

  Future<void> _exportFinancialStatement() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    try {
      final finance = context.read<FinanceProvider>();
      final sales = context.read<SalesProvider>();
      final shop = context.read<ShopProvider>().shop;
      final file = await PdfService.generateFinancialStatement(
        startDate: start,
        endDate: now,
        sales: sales.sales,
        expenses: finance.expenses,
        shop: shop,
      );
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'Shopkeeper Pro financial statement: ${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(now)}',
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export financial statement: $error')),
      );
    }
  }

  void _openAddExpenseDialog() {
    final labelCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedLabel = 'Shop Rent';
    const presets = ['Shop Rent', 'Electricity Bill', 'Employee Salaries', 'Miscellaneous'];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log Expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedLabel,
                items: [...presets, 'Other'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setDialogState(() => selectedLabel = v ?? selectedLabel),
              ),
              if (selectedLabel == 'Other')
                TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Expense Label')),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text);
                final label = selectedLabel == 'Other' ? labelCtrl.text.trim() : selectedLabel;
                if (amount == null || amount <= 0 || label.isEmpty) return;
                context.read<FinanceProvider>().addExpense(label, amount);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final finance = context.watch<FinanceProvider>();
    final sales = context.watch<SalesProvider>();
    final now = DateTime.now();
    final monthlySales = sales.sales.where((s) => s.date.year == now.year && s.date.month == now.month).toList();
    final revenue = monthlySales.fold(0.0, (sum, s) => sum + s.revenue);
    final cogs = monthlySales.fold(0.0, (sum, s) => sum + s.costOfGoods);
    final expensesTotal = finance.totalExpensesForMonth(now.year, now.month);
    final netProfit = finance.calculateNetProfit(monthlySales, now.year, now.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Export this month\'s financial statement PDF',
            onPressed: _exportFinancialStatement,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddExpenseDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: netProfit >= 0 ? AppTheme.teal.withValues(alpha: 0.12) : Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(DateFormat('MMMM yyyy').format(now), style: TextStyle(fontSize: 14, color: AppTheme.muted)),
                  const SizedBox(height: 4),
                  const Text('Clear Net Profit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    _currency.format(netProfit),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: netProfit >= 0 ? AppTheme.ink : Colors.red.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _statCard('Revenue', _currency.format(revenue), AppTheme.ink)),
              const SizedBox(width: 10),
              Expanded(child: _statCard('COGS', _currency.format(cogs), AppTheme.gold)),
              const SizedBox(width: 10),
              Expanded(child: _statCard('Expenses', _currency.format(expensesTotal), AppTheme.teal)),
            ],
          ),
          const SizedBox(height: 20),
          if (revenue > 0)
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(value: cogs, color: AppTheme.gold, title: 'COGS'),
                    PieChartSectionData(value: expensesTotal, color: AppTheme.teal, title: 'Expenses'),
                    PieChartSectionData(
                        value: netProfit > 0 ? netProfit : 0, color: AppTheme.ink, title: 'Profit'),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 30,
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Text('This Month\'s Expenses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...finance.expensesForMonth(now.year, now.month).map((e) => Card(
                child: ListTile(
                  title: Text(e.label),
                  subtitle: Text(DateFormat('dd MMM yyyy').format(e.date)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_currency.format(e.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => finance.deleteExpense(e.id),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) => Card(
        color: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: color)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
            ],
          ),
        ),
      );
}
