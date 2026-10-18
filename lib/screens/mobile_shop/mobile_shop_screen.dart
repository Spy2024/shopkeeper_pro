import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/mobile_device.dart';
import '../../services/mobile_shop_service.dart';
import '../../services/db_service.dart';
import '../../utils/theme.dart';

class MobileShopScreen extends StatefulWidget {
  const MobileShopScreen({super.key});

  @override
  State<MobileShopScreen> createState() => _MobileShopScreenState();
}

class _MobileShopScreenState extends State<MobileShopScreen> {
  final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0);
  List<MobileDevice> _devices = const [];
  List<MobileRepairJob> _jobs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        MobileShopService.instance.listDevices(),
        MobileShopService.instance.listRepairJobs(),
      ]);
      if (!mounted) return;
      setState(() {
        _devices = values[0] as List<MobileDevice>;
        _jobs = values[1] as List<MobileRepairJob>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone_iphone, color: AppTheme.teal),
              title: const Text('Add new mobile'),
              subtitle: const Text('Unit-wise stock with IMEI and warranty'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android, color: AppTheme.gold),
              title: const Text('Buy used mobile'),
              subtitle: const Text('Record seller, condition and purchase cost'),
              onTap: () => Navigator.pop(context, 'used'),
            ),
            ListTile(
              leading: const Icon(Icons.build_circle_outlined, color: AppTheme.ink),
              title: const Text('Create repair job'),
              subtitle: const Text('Job card, estimate and customer approval'),
              onTap: () => Navigator.pop(context, 'repair'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'new' || action == 'used') {
      await _showDeviceForm(used: action == 'used');
    } else {
      await _showRepairForm();
    }
  }

  Future<void> _showDeviceForm({required bool used}) async {
    final formKey = GlobalKey<FormState>();
    final brand = TextEditingController();
    final model = TextEditingController();
    final imei1 = TextEditingController();
    final imei2 = TextEditingController();
    final seller = TextEditingController();
    final sellerPhone = TextEditingController();
    final purchase = TextEditingController(text: '0');
    final repair = TextEditingController(text: '0');
    final selling = TextEditingController(text: '0');
    final condition = TextEditingController(text: used ? 'B' : 'New');
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.86),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      used ? 'Buy Used Mobile' : 'Add New Mobile',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      used ? 'Used phones stay in inspection until checked.' : 'Each physical device is recorded separately.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(controller: brand, decoration: const InputDecoration(labelText: 'Brand *'), validator: _required),
                    const SizedBox(height: 10),
                    TextFormField(controller: model, decoration: const InputDecoration(labelText: 'Model *'), validator: _required),
                    const SizedBox(height: 10),
                    TextFormField(controller: imei1, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'IMEI 1 *', helperText: '14–16 digits; duplicate IMEI is blocked'), validator: _requiredImei),
                    const SizedBox(height: 10),
                    TextFormField(controller: imei2, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'IMEI 2 (optional)'), validator: _optionalImei),
                    if (used) ...[
                      const SizedBox(height: 10),
                      TextFormField(controller: condition, decoration: const InputDecoration(labelText: 'Condition grade / notes')),
                      const SizedBox(height: 10),
                      TextFormField(controller: seller, decoration: const InputDecoration(labelText: 'Seller name (optional)')),
                      const SizedBox(height: 10),
                      TextFormField(controller: sellerPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Seller phone (optional)')),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextFormField(controller: purchase, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Purchase Rs. *'), validator: _money)),
                        const SizedBox(width: 10),
                        Expanded(child: TextFormField(controller: selling, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Sale Rs. *'), validator: _money)),
                      ],
                    ),
                    if (used) ...[
                      const SizedBox(height: 10),
                      TextFormField(controller: repair, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Initial repair cost Rs.'), validator: _money),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: saving ? null : () async {
                        if (!formKey.currentState!.validate()) return;
                        setSheetState(() => saving = true);
                        try {
                          await MobileShopService.instance.createDevice(
                            deviceType: used ? 'used' : 'new',
                            brand: brand.text,
                            model: model.text,
                            imei1: imei1.text,
                            imei2: imei2.text,
                            sellerName: used ? seller.text : null,
                            sellerPhone: used ? sellerPhone.text : null,
                            conditionGrade: used ? condition.text : 'New',
                            purchasePrice: double.parse(purchase.text),
                            repairCost: used ? double.parse(repair.text) : 0,
                            sellingPrice: double.parse(selling.text),
                            inspection: used ? const {'screen': 'pending', 'touch': 'pending', 'charging': 'pending', 'camera': 'pending', 'speakerMic': 'pending', 'network': 'pending', 'battery': 'pending'} : const {},
                          );
                          if (!mounted || !sheetContext.mounted) return;
                          Navigator.pop(sheetContext);
                          await _reload();
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save device: ${e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '')}')));
                        } finally {
                          if (sheetContext.mounted) setSheetState(() => saving = false);
                        }
                      },
                      icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                      label: Text(saving ? 'Saving…' : used ? 'Record Used Purchase' : 'Save New Mobile'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (final controller in [brand, model, imei1, imei2, seller, sellerPhone, purchase, repair, selling, condition]) {
      controller.dispose();
    }
  }

  Future<void> _showRepairForm() async {
    final formKey = GlobalKey<FormState>();
    final jobNumber = TextEditingController(text: 'JOB-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final customer = TextEditingController();
    final phone = TextEditingController();
    final brand = TextEditingController();
    final model = TextEditingController();
    final imei = TextEditingController();
    final issue = TextEditingController();
    final estimate = TextEditingController(text: '0');
    final approved = TextEditingController(text: '0');
    final advance = TextEditingController(text: '0');
    bool consent = false;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.86),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('New Repair Job Card', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink)),
                    const SizedBox(height: 14),
                    TextFormField(controller: jobNumber, decoration: const InputDecoration(labelText: 'Job number *'), validator: _required),
                    const SizedBox(height: 10),
                    TextFormField(controller: customer, decoration: const InputDecoration(labelText: 'Customer name *'), validator: _required),
                    const SizedBox(height: 10),
                    TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Customer phone')),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextFormField(controller: brand, decoration: const InputDecoration(labelText: 'Brand'))),
                      const SizedBox(width: 10),
                      Expanded(child: TextFormField(controller: model, decoration: const InputDecoration(labelText: 'Model'))),
                    ]),
                    const SizedBox(height: 10),
                    TextFormField(controller: imei, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'IMEI (optional)'), validator: _optionalImei),
                    const SizedBox(height: 10),
                    TextFormField(controller: issue, maxLines: 2, decoration: const InputDecoration(labelText: 'Reported issue *'), validator: _required),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextFormField(controller: estimate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Estimate Rs.'), validator: _money)),
                      const SizedBox(width: 10),
                      Expanded(child: TextFormField(controller: approved, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Approved total Rs.'), validator: _money)),
                    ]),
                    const SizedBox(height: 10),
                    TextFormField(controller: advance, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Advance received Rs.'), validator: _money),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: consent,
                      onChanged: (value) => setSheetState(() => consent = value ?? false),
                      title: const Text('Customer approved the work'),
                      subtitle: const Text('Approval is required before moving job to In progress.'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: saving ? null : () async {
                        if (!formKey.currentState!.validate()) return;
                        setSheetState(() => saving = true);
                        try {
                          await MobileShopService.instance.createRepairJob(
                            jobNumber: jobNumber.text,
                            customerName: customer.text,
                            customerPhone: phone.text,
                            brand: brand.text,
                            model: model.text,
                            imei: imei.text,
                            reportedIssue: issue.text,
                            estimateAmount: double.parse(estimate.text),
                            approvedAmount: double.parse(approved.text),
                            advancePaid: double.parse(advance.text),
                            customerConsent: consent,
                          );
                          if (!mounted || !sheetContext.mounted) return;
                          Navigator.pop(sheetContext);
                          await _reload();
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save repair job: ${e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '')}')));
                        } finally {
                          if (sheetContext.mounted) setSheetState(() => saving = false);
                        }
                      },
                      icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                      label: Text(saving ? 'Saving…' : 'Create Job Card'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (final controller in [jobNumber, customer, phone, brand, model, imei, issue, estimate, approved, advance]) {
      controller.dispose();
    }
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

  String? _money(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    return parsed == null || !parsed.isFinite || parsed < 0 ? 'Enter a valid amount' : null;
  }

  String? _requiredImei(String? value) {
    final normalized = normalizeImei(value);
    if (normalized.isEmpty) return 'IMEI is required';
    return normalized.length < 14 || normalized.length > 16 ? 'IMEI must be 14–16 digits' : null;
  }

  String? _optionalImei(String? value) {
    final normalized = normalizeImei(value);
    return normalized.isNotEmpty && (normalized.length < 14 || normalized.length > 16)
        ? 'IMEI must be 14–16 digits'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mobile Shop'),
          actions: [
            IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.phone_android), text: 'Devices'),
              Tab(icon: Icon(Icons.build_outlined), text: 'Repair Jobs'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showCreateMenu,
          icon: const Icon(Icons.add),
          label: const Text('Add / Create'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_off_outlined, size: 42, color: AppTheme.gold),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Try again')),
                      ]),
                    ),
                  )
                : TabBarView(
                    children: [
                      _buildDevices(),
                      _buildJobs(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildDevices() {
    final inStock = _devices.where((d) => d.status == 'in_stock').length;
    final used = _devices.where((d) => d.deviceType == 'used').length;
    final inspection = _devices.where((d) => d.status == 'inspection_pending').length;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.ink, Color(0xFF082B4C)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DEVICE INVENTORY', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('${_devices.length} devices registered', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _Metric(label: 'In stock', value: '$inStock', color: AppTheme.teal)),
                const SizedBox(width: 8),
                Expanded(child: _Metric(label: 'Used phones', value: '$used', color: AppTheme.gold)),
                const SizedBox(width: 8),
                Expanded(child: _Metric(label: 'Inspection', value: '$inspection', color: Colors.white)),
              ]),
            ]),
          ),
          const SizedBox(height: 8),
          if (_devices.isEmpty)
            const _EmptyState(icon: Icons.phone_android, title: 'No mobile devices yet', message: 'Add a new phone or record a used-phone purchase to begin.')
          else
            ..._devices.map((device) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: AppTheme.teal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.phone_iphone, color: AppTheme.teal),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${device.brand} ${device.model}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('${device.deviceType == 'used' ? 'Used' : 'New'} • ${device.status.replaceAll('_', ' ')}', style: TextStyle(color: device.status == 'in_stock' ? AppTheme.teal : AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                    if (device.imei1 != null) Text('IMEI: ${device.imei1}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _Pill(label: 'Cost ${_currency.format(device.totalKnownCost)}', color: AppTheme.ink),
                      _Pill(label: 'Sale ${_currency.format(device.sellingPrice)}', color: AppTheme.teal),
                    ]),
                  ])),
                  PopupMenuButton<String>(
                    tooltip: 'Update device status',
                    onSelected: (status) => _changeDeviceStatus(device, status),
                    itemBuilder: (_) => _deviceStatusOptions(device),
                  ),
                ]),
              ),
            )),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _deviceStatusOptions(MobileDevice device) {
    final options = <String, String>{};
    if (device.status == 'inspection_pending') {
      options['in_stock'] = 'Inspection passed / ready for stock';
      options['repair'] = 'Send to repair';
      options['rejected'] = 'Reject purchase';
    } else if (device.status == 'in_stock') {
      options['reserved'] = 'Reserve device';
      options['repair'] = 'Send to repair';
      options['written_off'] = 'Write off';
    } else if (device.status == 'reserved') {
      options['in_stock'] = 'Release reservation';
      options['repair'] = 'Send to repair';
    } else if (device.status == 'repair') {
      options['in_stock'] = 'Repair completed / back to stock';
      options['written_off'] = 'Write off';
    }
    return options.entries
        .map((entry) => PopupMenuItem<String>(value: entry.key, child: Text(entry.value)))
        .toList(growable: false);
  }

  Future<void> _changeDeviceStatus(MobileDevice device, String status) async {
    try {
      await MobileShopService.instance.updateDeviceStatus(device.id, status);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', ''))),
      );
    }
  }

  Future<void> _showRepairPaymentDialog(MobileRepairJob job) async {
    final amount = TextEditingController();
    var method = 'cash';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Payment · ${job.jobNumber}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Remaining balance: ${_currency.format(job.balanceDue)}'),
            TextField(controller: amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (Rs.)')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: const ['cash', 'card', 'bank', 'wallet', 'other']
                  .map((value) => DropdownMenuItem(value: value, child: Text(value.toUpperCase()))).toList(),
              onChanged: (value) => setDialogState(() => method = value ?? 'cash'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await MobileShopService.instance.recordRepairPayment(
                    jobId: job.id,
                    amount: double.parse(amount.text.trim()),
                    method: method,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  await _reload();
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('StateError: ', ''))));
                }
              },
              child: const Text('Save payment'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
  }

  Future<void> _showRepairPartDialog(MobileRepairJob job) async {
    final db = await DBService.instance.database;
    final products = await db.query('products', orderBy: 'name COLLATE NOCASE');
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add repair parts to inventory first.')));
      return;
    }
    var productId = products.first['id'] as String;
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController(text: ((products.first['sellingPrice'] as num?)?.toDouble() ?? 0).toString());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Use inventory part · ${job.jobNumber}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: productId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Inventory part'),
              items: products.map((row) => DropdownMenuItem<String>(
                value: row['id'] as String,
                child: Text('${row['name']} · stock ${row['stockQuantity']}'),
              )).toList(),
              onChanged: (value) {
                if (value == null) return;
                final selected = products.firstWhere((row) => row['id'] == value);
                setDialogState(() {
                  productId = value;
                  price.text = ((selected['sellingPrice'] as num?)?.toDouble() ?? 0).toString();
                });
              },
            ),
            TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
            TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Customer price per part (Rs.)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await MobileShopService.instance.consumeRepairPart(
                    jobId: job.id,
                    productId: productId,
                    quantity: int.parse(quantity.text.trim()),
                    unitPrice: double.parse(price.text.trim()),
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  await _reload();
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('StateError: ', ''))));
                }
              },
              child: const Text('Consume part'),
            ),
          ],
        ),
      ),
    );
    quantity.dispose();
    price.dispose();
  }

  Future<void> _showRepairWarrantyDialog(MobileRepairJob job) async {
    final days = TextEditingController(text: job.warrantyDays > 0 ? job.warrantyDays.toString() : '30');
    final terms = TextEditingController(text: 'Repair workmanship only');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Issue repair warranty · ${job.jobNumber}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Job must be marked Delivered first.'),
          TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Warranty days')),
          TextField(controller: terms, decoration: const InputDecoration(labelText: 'Warranty terms')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await MobileShopService.instance.issueRepairWarranty(
                  jobId: job.id,
                  warrantyDays: int.parse(days.text.trim()),
                  terms: terms.text.trim(),
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Repair warranty issued.')));
              } catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('StateError: ', ''))));
              }
            },
            child: const Text('Issue warranty'),
          ),
        ],
      ),
    );
    days.dispose();
    terms.dispose();
  }

  Future<void> _showRepairInvoice(MobileRepairJob job) async {
    try {
      final details = await MobileShopService.instance.repairInvoiceDetails(job.id);
      if (!mounted) return;
      final parts = details['parts'] as List<Map<String, Object?>>;
      final payments = details['payments'] as List<Map<String, Object?>>;
      final warranties = details['warranties'] as List<Map<String, Object?>>;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Repair invoice · ${job.jobNumber}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(job.customerName, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${job.brand ?? ''} ${job.model ?? ''} · IMEI ${job.imei ?? '—'}'),
                const Divider(),
                Text('Complaint: ${job.reportedIssue}'),
                Text('Approved total: ${_currency.format(job.approvedAmount)}'),
                Text('Parts cost: ${_currency.format(job.partsCost)}'),
                Text('Paid: ${_currency.format(job.advancePaid)}'),
                Text('Balance: ${_currency.format(job.balanceDue)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Parts used', style: TextStyle(fontWeight: FontWeight.w800)),
                if (parts.isEmpty) const Text('No parts consumed yet.'),
                for (final part in parts) Text('${part['partName']} × ${part['quantity']} · ${_currency.format(((part['unitPrice'] as num?)?.toDouble() ?? 0) * ((part['quantity'] as num?)?.toInt() ?? 0))}'),
                const SizedBox(height: 8),
                const Text('Payments', style: TextStyle(fontWeight: FontWeight.w800)),
                if (payments.isEmpty) const Text('No payments recorded yet.'),
                for (final payment in payments) Text('${payment['method']} · ${_currency.format((payment['amount'] as num).toDouble())}'),
                const SizedBox(height: 8),
                const Text('Warranty', style: TextStyle(fontWeight: FontWeight.w800)),
                if (warranties.isEmpty) const Text('No warranty issued.'),
                for (final warranty in warranties) Text('${warranty['status']} · expires ${warranty['expiresAt']}'),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('StateError: ', ''))));
    }
  }

  Future<void> _showRepairProfitReport() async {
    try {
      final report = await MobileShopService.instance.repairProfitReport();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Repair profit summary'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final entry in report.entries)
              ListTile(
                dense: true,
                title: Text(entry.key.replaceAllMapped(RegExp(r'[A-Z]'), (match) => ' ${match.group(0)!.toLowerCase()}').trim()),
                trailing: Text(_currency.format(entry.value), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _buildJobs() {
    final active = _jobs.where((j) => !{'delivered', 'cancelled', 'rejected'}.contains(j.status)).length;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.ink,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('REPAIR DESK', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('$active jobs in progress', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${_jobs.length} total job cards', style: const TextStyle(color: Colors.white70)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showRepairProfitReport,
                  icon: const Icon(Icons.insights, color: Colors.white),
                  label: const Text('Repair profit report', style: TextStyle(color: Colors.white)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (_jobs.isEmpty)
            const _EmptyState(icon: Icons.build_outlined, title: 'No repair jobs yet', message: 'Create a job card with the customer complaint, estimate and approval.')
          else
            ..._jobs.map((job) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(job.jobNumber, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                    _Pill(label: job.status.replaceAll('_', ' '), color: job.status == 'delivered' ? AppTheme.teal : AppTheme.gold),
                  ]),
                  const SizedBox(height: 6),
                  Text(job.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${job.brand ?? ''} ${job.model ?? ''}'.trim().isEmpty ? 'Device details not entered' : '${job.brand ?? ''} ${job.model ?? ''}'.trim()),
                  const SizedBox(height: 4),
                  Text(job.reportedIssue, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text('Balance: ${_currency.format(job.balanceDue)}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink))),
                    PopupMenuButton<String>(
                      tooltip: 'Update job status',
                      onSelected: (status) async {
                        try {
                          await MobileShopService.instance.updateRepairJobStatus(job.id, status);
                          await _reload();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('StateError: ', ''))));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'inspection', child: Text('Inspection')),
                        PopupMenuItem(value: 'estimate_sent', child: Text('Estimate sent')),
                        PopupMenuItem(value: 'awaiting_approval', child: Text('Awaiting approval')),
                        PopupMenuItem(value: 'in_progress', child: Text('In progress')),
                        PopupMenuItem(value: 'waiting_for_parts', child: Text('Waiting for parts')),
                        PopupMenuItem(value: 'quality_check', child: Text('Quality check')),
                        PopupMenuItem(value: 'ready', child: Text('Ready for pickup')),
                        PopupMenuItem(value: 'delivered', child: Text('Delivered')),
                        PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      TextButton.icon(onPressed: () => _showRepairInvoice(job), icon: const Icon(Icons.receipt_long_outlined), label: const Text('Invoice')),
                      TextButton.icon(onPressed: () => _showRepairPaymentDialog(job), icon: const Icon(Icons.payments_outlined), label: const Text('Payment')),
                      TextButton.icon(onPressed: () => _showRepairPartDialog(job), icon: const Icon(Icons.build_outlined), label: const Text('Use part')),
                      TextButton.icon(onPressed: () => _showRepairWarrantyDialog(job), icon: const Icon(Icons.verified_outlined), label: const Text('Warranty')),
                    ],
                  ),
                ]),
              ),
            )),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Metric({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(13)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    ]),
  );
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 18),
    child: Column(children: [
      Icon(icon, size: 42, color: AppTheme.teal),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 6),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
    ]),
  );
}
