import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/branch_report_service.dart';
import 'branch_management_screen.dart';

class BranchReportsScreen extends StatefulWidget {
  const BranchReportsScreen({super.key});

  @override
  State<BranchReportsScreen> createState() => _BranchReportsScreenState();
}

class _BranchReportsScreenState extends State<BranchReportsScreen> {
  final _service = BranchReportService.instance;
  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);
  List<Map<String, Object?>> _branches = [];
  String? _branchId;
  DateTimeRange _range = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1),
    end: DateTime.now(),
  );
  BranchReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await _service.activeBranches();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = branches.isEmpty ? null : branches.first['id'] as String;
        _loading = false;
      });
      await _loadReport();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadReport() async {
    final id = _branchId;
    if (id == null) {
      setState(() => _report = null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await _service.forPeriod(
        branchId: id,
        start: _range.start,
        end: _range.end,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (selected == null || !mounted) return;
    setState(() => _range = selected);
    await _loadReport();
  }

  Widget _metric(String label, double value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(
          _currency.format(value),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Reports'),
        actions: [
          IconButton(
            tooltip: 'Manage branches',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BranchManagementScreen()),
            ),
            icon: const Icon(Icons.store_mall_directory_outlined),
          ),
          IconButton(
            tooltip: 'Choose date range',
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
          ),
          IconButton(
            tooltip: 'Refresh report',
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _branches.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_branches.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _branchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(),
                    ),
                    items: _branches.map((branch) {
                      final id = branch['id'] as String;
                      final name = (branch['name'] as String?) ?? id;
                      final code = (branch['code'] as String?) ?? '';
                      return DropdownMenuItem(
                        value: id,
                        child: Text(code.isEmpty ? name : '$name ($code)'),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      setState(() => _branchId = value);
                      await _loadReport();
                    },
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.calendar_month),
                  label: Text('${dateFormat.format(_range.start)} – ${dateFormat.format(_range.end)}'),
                ),
                const SizedBox(height: 8),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Could not load report: $_error'),
                    ),
                  )
                else if (_branches.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No active branches found. Create or activate a branch first.'),
                    ),
                  )
                else if (!_loading && _report != null) ...[
                  _metric('Recorded sales', _report!.revenue, Icons.trending_up),
                  _metric('Expenses', _report!.expenses, Icons.money_off),
                  _metric('Net sales less expenses', _report!.netOperatingResult, Icons.account_balance),
                  _metric('Cash received', _report!.cashReceived, Icons.payments_outlined),
                  _metric('Cash out', _report!.cashOut, Icons.outbound_outlined),
                  _metric('Udhaar issued', _report!.creditIssued, Icons.credit_score_outlined),
                  const SizedBox(height: 8),
                  const Text(
                    'Report totals use branch-tagged local records. Verify historical records have branch IDs before relying on comparisons.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
    );
  }
}