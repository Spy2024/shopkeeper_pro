import 'package:flutter/material.dart';
import '../../services/business_operations_service.dart';
import '../../services/db_service.dart';

class BusinessManagementScreen extends StatefulWidget {
  const BusinessManagementScreen({super.key});

  @override
  State<BusinessManagementScreen> createState() => _BusinessManagementScreenState();
}

class _BusinessManagementScreenState extends State<BusinessManagementScreen> with SingleTickerProviderStateMixin {
  final _ops = BusinessOperationsService.instance;
  late final TabController _tabs;
  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _branches = [];
  List<Map<String, Object?>> _products = [];
  List<Map<String, Object?>> _bills = [];
  List<Map<String, Object?>> _routes = [];
  List<Map<String, Object?>> _restaurantTables = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final db = await DBService.instance.database;
      final customers = await db.query('customers', orderBy: 'name COLLATE NOCASE');
      final branches = await db.query('branches', orderBy: 'name COLLATE NOCASE');
      final products = await db.query('products', orderBy: 'name COLLATE NOCASE');
      final bills = await db.query('bills', orderBy: 'date DESC', limit: 100);
      final routes = await db.query('transport_routes', orderBy: 'name COLLATE NOCASE');
      final restaurantTables = await db.query('restaurant_tables', orderBy: 'name COLLATE NOCASE');
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _branches = branches;
        _products = products;
        _bills = bills;
        _routes = routes;
        _restaurantTables = restaurantTables;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString(); _loading = false; });
    }
  }

  Future<Map<String, String>?> _form(String title, List<(String, String)> fields) async {
    final controllers = <String, TextEditingController>{
      for (final field in fields) field.$1: TextEditingController(),
    };
    String? error;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in fields)
                  TextField(
                    controller: controllers[field.$1],
                    keyboardType: field.$2.contains('number') ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                    decoration: InputDecoration(labelText: field.$1),
                  ),
                if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final values = {for (final entry in controllers.entries) entry.key: entry.value.text.trim()};
                final missing = fields.where((f) => f.$2.startsWith('required') && (values[f.$1] ?? '').isEmpty);
                if (missing.isNotEmpty) {
                  setDialogState(() => error = '${missing.first.$1} is required.');
                  return;
                }
                Navigator.pop(dialogContext, values);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  Future<void> _addCustomer() async {
    final v = await _form('Add customer', [('Name', 'required'), ('Phone', 'text'), ('Address', 'text'), ('Email', 'text')]);
    if (v == null) return;
    try {
      await _ops.addCustomer(name: v['Name']!, phone: v['Phone'], address: v['Address'], email: v['Email']);
      await _reload();
    } catch (e) { _showError(e); }
  }

  Future<void> _addLedgerEntry(Map<String, Object?> customer) async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Ledger · ${customer['name']}'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'credit'), child: const Text('Add udhaar / credit')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'payment'), child: const Text('Record customer payment')),
        ],
      ),
    );
    if (type == null) return;
    final v = await _form(type == 'credit' ? 'Add udhaar' : 'Receive payment', [('Amount (Rs.)', 'required_number'), ('Note', 'text')]);
    if (v == null) return;
    final amount = double.tryParse(v['Amount (Rs.)'] ?? '');
    if (amount == null || amount <= 0) { _showError('Enter a valid positive amount.'); return; }
    try {
      await _ops.recordCustomerLedgerEntry(customerId: customer['id']! as String, type: type, amount: amount, note: v['Note']);
      await _reload();
    } catch (e) { _showError(e); }
  }

  Future<void> _addBranch() async {
    final v = await _form('Add branch', [('Name', 'required'), ('Address', 'text'), ('Phone', 'text')]);
    if (v == null) return;
    try {
      await _ops.createBranch(name: v['Name']!, address: v['Address'], phone: v['Phone']);
      await _reload();
    } catch (e) { _showError(e); }
  }

  Future<void> _branchCash(Map<String, Object?> branch) async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Cash · ${branch['name']}'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'in'), child: const Text('Cash received (in)')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'out'), child: const Text('Cash paid (out)')),
        ],
      ),
    );
    if (type == null) return;
    final v = await _form('Branch cash entry', [('Amount (Rs.)', 'required'), ('Note', 'text')]);
    if (v == null) return;
    final amount = double.tryParse(v['Amount (Rs.)'] ?? '');
    if (amount == null || amount <= 0) { _showError('Enter a valid positive amount.'); return; }
    try {
      await _ops.recordBranchCash(branchId: branch['id']! as String, type: type, amount: amount, note: v['Note']);
      final report = await _ops.branchReport(branch['id']! as String);
      if (mounted) _showMessage('Cash balance: Rs. ${report['cashBalance']}');
      await _reload();
    } catch (e) { _showError(e); }
  }

  Future<void> _showBranchReport(Map<String, Object?> branch) async {
    try {
      final report = await _ops.branchReport(branch['id']! as String);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${branch['name']} report'),
          content: Text('Total units in branch stock: ${report['stockUnits']}\nCash balance: Rs. ${report['cashBalance']}'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) { _showError(e); }
  }

  Future<void> _setBranchStock(Map<String, Object?> branch) async {
    if (_products.isEmpty) { _showError('Pehle inventory mein product add karein.'); return; }
    final product = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose product'),
        children: _products.map((p) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, p),
          child: Text('${p['name']} (current stock: ${p['stockQuantity']})'),
        )).toList(),
      ),
    );
    if (product == null) return;
    final v = await _form('Branch stock · ${branch['name']}', [('Quantity', 'required_number')]);
    if (v == null) return;
    final quantity = int.tryParse(v['Quantity'] ?? '');
    if (quantity == null || quantity < 0) { _showError('Quantity zero ya positive number honi chahiye.'); return; }
    try {
      await _ops.setBranchStock(branchId: branch['id']! as String, productId: product['id']! as String, quantity: quantity);
      await _reload();
      _showMessage('Branch stock saved.');
    } catch (e) { _showError(e); }
  }

  Future<void> _createRestaurantOrder() async {
    final available = _restaurantTables.where((t) => t['status'] == 'available').toList();
    if (available.isEmpty) { _showError('Pehle available restaurant table add karein.'); return; }
    final table = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose available table'),
        children: available.map((t) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, t),
          child: Text('${t['name']} · capacity ${t['capacity']}'),
        )).toList(),
      ),
    );
    if (table == null) return;
    final v = await _form('Restaurant order', [('Total amount (Rs.)', 'required_number')]);
    if (v == null) return;
    final total = double.tryParse(v['Total amount (Rs.)'] ?? '');
    if (total == null || total < 0) { _showError('Enter a valid total.'); return; }
    try {
      await _ops.createRestaurantOrder(tableId: table['id']! as String, total: total);
      await _reload();
      _showMessage('Restaurant order created and table marked occupied.');
    } catch (e) { _showError(e); }
  }

  Future<void> _addTransportTicket() async {
    if (_routes.isEmpty) { _showError('Pehle transport route banayein.'); return; }
    final route = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose route'),
        children: _routes.map((r) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, r),
          child: Text('${r['name']} · ${r['origin'] ?? ''} → ${r['destination'] ?? ''}'),
        )).toList(),
      ),
    );
    if (route == null) return;
    final v = await _form('Passenger ticket', [('Passenger name', 'required'), ('Travel date (YYYY-MM-DD)', 'required'), ('Fare (Rs.)', 'required_number'), ('Seat number', 'text')]);
    if (v == null) return;
    final fare = double.tryParse(v['Fare (Rs.)'] ?? '');
    if (fare == null || fare < 0) { _showError('Enter a valid fare.'); return; }
    try {
      await _ops.addTransportTicket(routeId: route['id']! as String, passengerName: v['Passenger name']!, travelDate: v['Travel date (YYYY-MM-DD)']!, fare: fare, seatNumber: v['Seat number']);
      _showMessage('Passenger ticket saved.');
    } catch (e) { _showError(e); }
  }

  Future<void> _processReturn() async {
    final v = await _form('Process return / refund', [
      ('Bill ID', 'required'), ('Product name', 'required'),
      ('Quantity', 'required_number'), ('Unit price (Rs.)', 'required_number'),
      ('Refund amount (Rs.)', 'required_number'), ('IMEI (if phone return)', 'text'), ('Customer name', 'text'), ('Reason', 'text'),
    ]);
    if (v == null) return;
    final quantity = int.tryParse(v['Quantity'] ?? '');
    final price = double.tryParse(v['Unit price (Rs.)'] ?? '');
    final refund = double.tryParse(v['Refund amount (Rs.)'] ?? '');
    if (quantity == null || quantity < 1 || price == null || price < 0 || refund == null || refund < 0) {
      _showError('Quantity, price or refund amount is invalid.'); return;
    }
    try {
      await _ops.processReturn(
        billId: v['Bill ID']!, items: [ReturnLine(productName: v['Product name']!, imei: (v['IMEI (if phone return)'] ?? '').trim().isEmpty ? null : v['IMEI (if phone return)']!.trim(), quantity: quantity, unitPrice: price)],
        refundAmount: refund, customerName: v['Customer name'], reason: v['Reason'],
      );
      await _reload();
      _showMessage('Return saved and stock restored.');
    } catch (e) { _showError(e); }
  }

  Future<void> _addVerticalRecord(String type) async {
    try {
      Map<String, String>? v;
      switch (type) {
        case 'IMEI mobile':
          if (_products.isEmpty) { _showError('Pehle inventory mein phone model add karein.'); return; }
          final phoneProduct = await showDialog<Map<String, Object?>>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Choose phone model'),
              children: _products.map((p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: Text(p['name']! as String),
              )).toList(),
            ),
          );
          if (phoneProduct == null) return;
          v = await _form('Register phone by IMEI', [('IMEI (15 digits)', 'required'), ('Purchase price', 'number'), ('Sale price', 'number')]);
          if (v != null) await _ops.addMobileDevice(productId: phoneProduct['id']! as String, imei: v['IMEI (15 digits)']!, purchasePrice: double.tryParse(v['Purchase price'] ?? '') ?? 0, salePrice: double.tryParse(v['Sale price'] ?? '') ?? 0);
          break;
        case 'Restaurant table':
          v = await _form('Add restaurant table', [('Table name/number', 'required'), ('Capacity', 'number')]);
          if (v != null) await _ops.createRestaurantTable(name: v['Table name/number']!, capacity: int.tryParse(v['Capacity'] ?? '') ?? 2);
          break;
        case 'Vehicle showroom':
          v = await _form('Add vehicle record', [('Type (car/bike/etc.)', 'required'), ('Make', 'text'), ('Model', 'text'), ('Registration number', 'text'), ('VIN/chassis', 'text'), ('Purchase price', 'number'), ('Sale price', 'number')]);
          if (v != null) await _ops.addVehicleRecord(type: v['Type (car/bike/etc.)']!, make: v['Make'], model: v['Model'], registrationNumber: v['Registration number'], vin: v['VIN/chassis'], purchasePrice: double.tryParse(v['Purchase price'] ?? '') ?? 0, salePrice: double.tryParse(v['Sale price'] ?? '') ?? 0);
          break;
        case 'Transport route':
          v = await _form('Add passenger/cargo route', [('Route name', 'required'), ('Origin', 'text'), ('Destination', 'text')]);
          if (v != null) await _ops.addTransportRoute(name: v['Route name']!, origin: v['Origin'], destination: v['Destination']);
          break;
        case 'Cargo job':
          v = await _form('Create cargo/load job', [('Customer name', 'required'), ('Load description', 'text'), ('Weight', 'number'), ('Freight amount', 'number')]);
          if (v != null) await _ops.createCargoJob(customerName: v['Customer name']!, loadDescription: v['Load description'], weight: double.tryParse(v['Weight'] ?? '') ?? 0, freightAmount: double.tryParse(v['Freight amount'] ?? '') ?? 0);
          break;
        case 'Spare part compatibility':
          if (_products.isEmpty) { _showError('Pehle spare-part product inventory mein add karein.'); return; }
          final partProduct = await showDialog<Map<String, Object?>>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Choose spare-part product'),
              children: _products.map((p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: Text(p['name']! as String),
              )).toList(),
            ),
          );
          if (partProduct == null) return;
          v = await _form('Spare part compatibility', [
            ('Part type: bike/car/mobile/other', 'required'),
            ('Make', 'text'), ('Model', 'text'),
            ('Year from', 'number'), ('Year to', 'number'),
            ('Engine code', 'text'), ('Notes', 'text'),
          ]);
          if (v != null) {
            await _ops.addSparePartCompatibility(
              productId: partProduct['id']! as String,
              partType: v['Part type: bike/car/mobile/other']!.toLowerCase(),
              make: v['Make'], model: v['Model'],
              yearFrom: int.tryParse(v['Year from'] ?? ''),
              yearTo: int.tryParse(v['Year to'] ?? ''),
              engineCode: v['Engine code'], notes: v['Notes'],
            );
          }
          break;
        case 'Repair/service job':
          v = await _form('Create repair/service job', [('Customer name', 'required'), ('Device/vehicle', 'text'), ('Issue / complaint', 'required'), ('Estimated cost', 'number')]);
          if (v != null) await _ops.createServiceJob(customerName: v['Customer name']!, deviceOrVehicle: v['Device/vehicle'], issue: v['Issue / complaint']!, estimatedCost: double.tryParse(v['Estimated cost'] ?? '') ?? 0);
          break;
        case 'Clothing/product variant':
          final product = await showDialog<Map<String, String>>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Choose parent product'),
              children: _products.map((p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, {'id': p['id']! as String, 'name': p['name']! as String}),
                child: Text(p['name']! as String),
              )).toList(),
            ),
          );
          if (product == null) return;
          v = await _form('Add size/color variant', [('Size', 'text'), ('Color', 'text'), ('SKU', 'text'), ('Quantity', 'number')]);
          if (v != null) await _ops.addProductVariant(productId: product['id']!, size: v['Size'], color: v['Color'], sku: v['SKU'], quantity: int.tryParse(v['Quantity'] ?? '') ?? 0);
          break;
      }
      if (v != null) { await _reload(); _showMessage('$type record saved.'); }
    } catch (e) { _showError(e); }
  }

  void _showError(Object error) {
    if (mounted) _showMessage('Error: $error');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Management'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(icon: Icon(Icons.people_outline), text: 'Customers'),
          Tab(icon: Icon(Icons.store_mall_directory_outlined), text: 'Branches'),
          Tab(icon: Icon(Icons.category_outlined), text: 'Modules'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!)))
              : TabBarView(controller: _tabs, children: [
                  _customerTab(),
                  _branchTab(),
                  _modulesTab(),
                ]),
    );
  }

  Widget _customerTab() => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _addCustomer, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add customer')))),
    Expanded(child: _customers.isEmpty ? const Center(child: Text('No customers yet')) : ListView.builder(
      itemCount: _customers.length,
      itemBuilder: (context, i) {
        final customer = _customers[i];
        return FutureBuilder<double>(
          future: _ops.customerBalance(customer['id']! as String),
          builder: (context, snapshot) => ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(customer['name']! as String),
            subtitle: Text('${customer['phone'] ?? 'No phone'} · Balance: Rs. ${(snapshot.data ?? 0).toStringAsFixed(2)}'),
            trailing: IconButton(icon: const Icon(Icons.add_card), tooltip: 'Add udhaar/payment', onPressed: () => _addLedgerEntry(customer)),
          ),
        );
      },
    )),
  ]);

  Widget _branchTab() => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _addBranch, icon: const Icon(Icons.add_business), label: const Text('Add branch')))),
    Expanded(child: _branches.isEmpty ? const Center(child: Text('No branches yet')) : ListView.builder(
      itemCount: _branches.length,
      itemBuilder: (context, i) {
        final branch = _branches[i];
        return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), child: ListTile(
          title: Text(branch['name']! as String),
          subtitle: Text('${branch['address'] ?? ''} · ${branch['phone'] ?? ''}'),
          trailing: PopupMenuButton<String>(
            onSelected: (v) { if (v == 'cash') _branchCash(branch); if (v == 'report') _showBranchReport(branch); if (v == 'stock') _setBranchStock(branch); },
            itemBuilder: (_) => const [PopupMenuItem(value: 'cash', child: Text('Record cash in/out')), PopupMenuItem(value: 'stock', child: Text('Set branch stock')), PopupMenuItem(value: 'report', child: Text('View branch report'))],
          ),
        ));
      },
    )),
  ]);

  Widget _modulesTab() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Card(child: ListTile(leading: const Icon(Icons.assignment_return), title: const Text('Returns & refunds'), subtitle: const Text('Record return, refund and restore stock'), trailing: const Icon(Icons.chevron_right), onTap: _processReturn)),
      Card(child: ListTile(leading: const Icon(Icons.restaurant_menu), title: const Text('Restaurant order'), subtitle: const Text('Open order and reserve an available table'), trailing: const Icon(Icons.add_circle_outline), onTap: _createRestaurantOrder)),
      Card(child: ListTile(leading: const Icon(Icons.confirmation_number_outlined), title: const Text('Passenger ticket'), subtitle: const Text('Book route, passenger, seat and fare'), trailing: const Icon(Icons.add_circle_outline), onTap: _addTransportTicket)),
      const Padding(padding: EdgeInsets.all(8), child: Text('Business-specific records', style: TextStyle(fontWeight: FontWeight.bold))),
      for (final item in const [
        ('IMEI mobile', Icons.phone_android, 'Register box-pack/used phone by unique IMEI'),
        ('Clothing/product variant', Icons.checkroom, 'Track size, color, SKU and quantity'),
        ('Restaurant table', Icons.restaurant, 'Create restaurant table/capacity'),
        ('Vehicle showroom', Icons.directions_car, 'Record car, bike or other vehicle'),
        ('Transport route', Icons.route, 'Create passenger/cargo route'),
        ('Cargo job', Icons.local_shipping, 'Record load, weight and freight'),
        ('Repair/service job', Icons.build, 'Track repair issue and estimate'),
        ('Spare part compatibility', Icons.settings_suggest_outlined, 'Map bike/car/mobile parts to make, model and year'),
      ])
        Card(child: ListTile(
          leading: Icon(item.$2),
          title: Text(item.$1),
          subtitle: Text(item.$3),
          trailing: const Icon(Icons.add_circle_outline),
          onTap: () => _addVerticalRecord(item.$1),
        )),
      if (_bills.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No bills available for return selection. Enter an existing Bill ID to process a return.', style: TextStyle(color: Colors.grey))),
    ],
  );
}
