import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/business_operations_service.dart';
import '../../services/db_service.dart';
import 'business_verticals_screen.dart';
import 'snooker_club_screen.dart';

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
    await _ops.createRestaurantOrder(tableId: table['id']! as String);
  }

  Future<void> _addRestaurantOrderItem() async {
    final db = await DBService.instance.database;
    final orders = await db.query('restaurant_orders', where: 'status = ?', whereArgs: ['open'], orderBy: 'createdAt DESC');
    final menu = await db.query('restaurant_menu_items', where: 'active = 1', orderBy: 'name');
    if (!mounted) return;
    if (orders.isEmpty || menu.isEmpty) { _showError('Open restaurant order aur active menu item pehle banayein.'); return; }
    final order = await showDialog<Map<String, Object?>>(
      context: context, builder: (context) => SimpleDialog(title: const Text('Choose open order'),
        children: orders.map((row) => SimpleDialogOption(onPressed: () => Navigator.pop(context, row), child: Text('Order ${row['id']} · total Rs. ${row['total']}'))).toList()));
    if (order == null || !mounted) return;
    final item = await showDialog<Map<String, Object?>>(
      context: context, builder: (context) => SimpleDialog(title: const Text('Choose menu item'),
        children: menu.map((row) => SimpleDialogOption(onPressed: () => Navigator.pop(context, row), child: Text('${row['name']} · Rs. ${row['price']}'))).toList()));
    if (item == null || !mounted) return;
    final v = await _form('Add item to restaurant order', [('Quantity', 'required_number'), ('Kitchen note', 'text')]);
    if (v == null) return;
    await _ops.addRestaurantOrderItem(orderId: order['id']! as String, menuItemId: item['id']! as String, quantity: int.tryParse(v['Quantity'] ?? '') ?? 0, notes: v['Kitchen note']);
    await _reload(); _showMessage('Kitchen order item queued.');
  }

  Future<void> _recordRestaurantPaymentFromList() async {
    final db = await DBService.instance.database;
    final orders = await db.query('restaurant_orders',
        where: 'status = ?', whereArgs: ['open'], orderBy: 'createdAt DESC');
    if (!mounted) return;
    if (orders.isEmpty) {
      _showError('Koi open restaurant order nahi hai.');
      return;
    }
    final order = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose order for payment'),
        children: orders.map((row) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, row),
          child: Text('Order ${row['id']} · Rs. ${row['total']}'),
        )).toList(),
      ),
    );
    if (order == null || !mounted) return;
    final v = await _form('Restaurant payment', [
      ('Method (cash/card/bank)', 'required'),
      ('Amount (Rs.)', 'required_number'),
      ('Reference (optional)', 'text'),
    ]);
    if (v == null) return;
    final amount = double.tryParse(v['Amount (Rs.)'] ?? '');
    if (amount == null || amount <= 0) {
      _showError('Payment amount positive hona chahiye.');
      return;
    }
    await _ops.recordRestaurantPayment(
      orderId: order['id']! as String,
      payments: [PaymentLine(
        method: v['Method (cash/card/bank)']!,
        amount: amount,
        reference: v['Reference (optional)'],
      )],
    );
    await _reload();
    _showMessage('Restaurant payment recorded. Kitchen items served/cancelled hon to order close karein.');
  }

  Future<void> _completeRestaurantOrderFromList() async {
    final db = await DBService.instance.database;
    final orders = await db.query('restaurant_orders',
        where: 'status = ?', whereArgs: ['open'], orderBy: 'createdAt DESC');
    if (!mounted) return;
    if (orders.isEmpty) {
      _showError('Koi open restaurant order nahi hai.');
      return;
    }
    final order = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Complete restaurant order'),
        children: orders.map((row) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, row),
          child: Text('Order ${row['id']} · Rs. ${row['total']}'),
        )).toList(),
      ),
    );
    if (order == null) return;
    await _ops.completeRestaurantOrder(order['id']! as String);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    _showMessage('Paid restaurant order completed and table released.');
  }

  Future<void> _updateRestaurantKitchen() async {
    final db = await DBService.instance.database;
    final items = await db.query('restaurant_order_items', where: 'kitchenStatus NOT IN (?, ?)', whereArgs: ['served','cancelled']);
    if (!mounted) return;
    if (items.isEmpty) { _showError('No pending kitchen items.'); return; }
    final item = await showDialog<Map<String, Object?>>(
      context: context, builder: (context) => SimpleDialog(title: const Text('Choose kitchen item'),
        children: items.map((row) => SimpleDialogOption(onPressed: () => Navigator.pop(context, row), child: Text('Order ${row['orderId']} · ${row['quantity']} pcs · ${row['kitchenStatus']}'))).toList()));
    if (item == null || !mounted) return;
    final status = await showDialog<String>(context: context, builder: (context) => SimpleDialog(title: const Text('Kitchen status'),
      children: ['queued','preparing','ready','served','cancelled'].map((s) => SimpleDialogOption(onPressed: () => Navigator.pop(context, s), child: Text(s))).toList()));
    if (status == null) return;
    await _ops.updateKitchenStatus(orderItemId: item['id']! as String, status: status);
    await _reload(); _showMessage('Kitchen status updated.');
  }

  Future<void> _recordVehicleTransactionFromList() async {
    final db = await DBService.instance.database;
    final vehicles = await db.query('vehicle_records', orderBy: 'make, model');
    if (!mounted) return;
    if (vehicles.isEmpty) { _showError('Pehle vehicle record add karein.'); return; }
    final vehicle = await showDialog<Map<String, Object?>>(context: context, builder: (context) => SimpleDialog(title: const Text('Choose vehicle'),
      children: vehicles.map((v) => SimpleDialogOption(onPressed: () => Navigator.pop(context, v), child: Text('${v['make'] ?? ''} ${v['model'] ?? ''} · ${v['registrationNumber'] ?? v['id']}'))).toList()));
    if (vehicle == null || !mounted) return;
    final v = await _form('Vehicle purchase/sale', [('Type: purchase/sale/expense', 'required'), ('Party name', 'required'), ('Amount', 'required_number'), ('Notes', 'text')]);
    if (v == null) return;
    await _ops.recordVehicleTransaction(vehicleId: vehicle['id']! as String, type: v['Type: purchase/sale']!.toLowerCase(), partyName: v['Party name']!, amount: double.tryParse(v['Amount'] ?? '') ?? 0, notes: v['Notes']);
    await _reload(); _showMessage('Vehicle transaction saved.');
  }

  Future<void> _showVehicleProfitReport() async {
    final rows = await _ops.vehicleProfitReport();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vehicle profit report'),
        content: SizedBox(
          width: 560,
          child: rows.isEmpty
              ? const Text('No vehicle transactions found.')
              : ListView(
                  shrinkWrap: true,
                  children: rows.map((row) {
                    final name = '${row['make'] ?? ''} ${row['model'] ?? ''} ${row['registrationNumber'] ?? ''}'.trim();
                    final profit = (row['netProfit'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      title: Text(name.isEmpty ? 'Vehicle ${row['vehicleId']}' : name),
                      subtitle: Text('Sale: Rs. ${row['saleProceeds']} · Purchase: Rs. ${row['purchaseCost']} · Expenses: Rs. ${row['expenses']}'),
                      trailing: Text('Rs. ${profit.toStringAsFixed(2)}'),
                    );
                  }).toList(),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _updateCargoTrackingFromList() async {
    final db = await DBService.instance.database;
    final jobs = await db.query('cargo_jobs', where: 'status != ?', whereArgs: ['delivered']);
    if (!mounted) return;
    if (jobs.isEmpty) { _showError('No active cargo jobs.'); return; }
    final job = await showDialog<Map<String, Object?>>(context: context, builder: (context) => SimpleDialog(title: const Text('Choose cargo job'),
      children: jobs.map((j) => SimpleDialogOption(onPressed: () => Navigator.pop(context, j), child: Text('${j['customerName']} · ${j['status']} · ${j['id']}'))).toList()));
    if (job == null || !mounted) return;
    final v = await _form('Update cargo tracking', [('Status: created/picked_up/in_transit/at_hub/out_for_delivery/delivered/cancelled', 'required'), ('Current location', 'text'), ('Note', 'text')]);
    if (v == null) return;
    await _ops.updateCargoStatus(cargoId: job['id']! as String, status: v['Status: created/picked_up/in_transit/at_hub/out_for_delivery/delivered/cancelled']!, location: v['Current location'], note: v['Note']);
    await _reload(); _showMessage('Cargo tracking updated.');
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
          if (v != null) {
            final cargoId = await _ops.createCargoJob(customerName: v['Customer name']!, loadDescription: v['Load description'], weight: double.tryParse(v['Weight'] ?? '') ?? 0, freightAmount: double.tryParse(v['Freight amount'] ?? '') ?? 0);
            final db = await DBService.instance.database;
            final cargo = (await db.query('cargo_jobs', where: 'id = ?', whereArgs: [cargoId])).single;
            final token = cargo['trackingToken']! as String;
            final trackingUrl = 'https://shopkeeper-2de9a.web.app/api/track?token=$token';
            if (mounted) {
              await showDialog<void>(context: context, builder: (context) => AlertDialog(
              title: const Text('Customer cargo tracking link'),
              content: SelectableText(trackingUrl),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                FilledButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: trackingUrl)); if (context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.copy), label: const Text('Copy link')),
              ],
              ));
            }
          }
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
        case 'School student':
          v = await _form('Add school student', [('Student name', 'required'), ('Guardian name', 'text'), ('Phone', 'text'), ('Class/grade', 'text')]);
          if (v != null) await _ops.addSchoolStudent(name: v['Student name']!, guardianName: v['Guardian name'], phone: v['Phone'], className: v['Class/grade']);
          break;
        case 'Clinic patient':
          v = await _form('Register clinic patient', [('Patient name', 'required'), ('Phone', 'text'), ('Date of birth', 'text'), ('Notes', 'text')]);
          if (v != null) await _ops.addClinicPatient(name: v['Patient name']!, phone: v['Phone'], dateOfBirth: v['Date of birth'], notes: v['Notes']);
          break;
        case 'Salon service':
          v = await _form('Add salon service', [('Service name', 'required'), ('Duration minutes', 'number'), ('Price', 'number')]);
          if (v != null) await _ops.addSalonService(name: v['Service name']!, durationMinutes: int.tryParse(v['Duration minutes'] ?? '') ?? 30, price: double.tryParse(v['Price'] ?? '') ?? 0);
          break;
        case 'Agriculture plot':
          v = await _form('Add farm plot', [('Plot name', 'required'), ('Area (acres)', 'required_number'), ('Crop', 'required'), ('Season', 'text')]);
          if (v != null) await _ops.addFarmPlot(name: v['Plot name']!, area: double.tryParse(v['Area (acres)'] ?? '') ?? 0, crop: v['Crop']!, season: v['Season']);
          break;
        case 'Construction project':
          v = await _form('Add construction project', [('Project name', 'required'), ('Client', 'text'), ('Location', 'text'), ('Budget', 'number'), ('Due date', 'text')]);
          if (v != null) await _ops.addConstructionProject(name: v['Project name']!, clientName: v['Client'], location: v['Location'], budget: double.tryParse(v['Budget'] ?? '') ?? 0, dueDate: v['Due date']);
          break;
        case 'Public service case':
          v = await _form('Open public service case', [('Case number', 'required'), ('Applicant name', 'required'), ('Service type', 'required'), ('Fee', 'number'), ('Notes', 'text')]);
          if (v != null) await _ops.addPublicServiceCase(caseNumber: v['Case number']!, applicantName: v['Applicant name']!, serviceType: v['Service type']!, fee: double.tryParse(v['Fee'] ?? '') ?? 0, notes: v['Notes']);
          break;
        case 'Add item to restaurant order':
          await _addRestaurantOrderItem();
          break;
        case 'Update restaurant kitchen':
          await _updateRestaurantKitchen();
          break;
        case 'Restaurant payment':
          await _recordRestaurantPaymentFromList();
          break;
        case 'Complete restaurant order':
          await _completeRestaurantOrderFromList();
          break;
        case 'Restaurant menu item':
          v = await _form('Add restaurant menu item', [('Item name', 'required'), ('Category', 'text'), ('Price', 'required_number')]);
          if (v != null) await _ops.addRestaurantMenuItem(name: v['Item name']!, category: v['Category'], price: double.tryParse(v['Price'] ?? '') ?? 0);
          break;
        case 'Vehicle purchase/sale':
          await _recordVehicleTransactionFromList();
          break;
        case 'Vehicle profit report':
          await _showVehicleProfitReport();
          break;
        case 'Cargo status tracking':
          await _updateCargoTrackingFromList();
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
      Card(child: ListTile(leading: const Icon(Icons.sports_esports_outlined), title: const Text('Snooker Club'), subtitle: const Text('Tables, games, winner/loser, game fees, refreshments POS, cash closing, cues, ball sets and lockers'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SnookerClubScreen())))),
      Card(child: ListTile(leading: const Icon(Icons.analytics_outlined), title: const Text('Business workflows & reports'), subtitle: const Text('School fees, clinic payments, salon bookings, farm costs, construction tasks and public cases'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessVerticalsScreen())))),
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
        ('School student', Icons.school, 'Student admission and guardian records'),
        ('Clinic patient', Icons.medical_services, 'Patient records for appointments'),
        ('Salon service', Icons.content_cut, 'Service price and duration'),
        ('Agriculture plot', Icons.agriculture, 'Farm plots, crop and season'),
        ('Construction project', Icons.construction, 'Project budget and client'),
        ('Public service case', Icons.account_balance, 'Applicant and service case tracking'),
        ('Restaurant menu item', Icons.restaurant_menu, 'Menu price and kitchen order support'),
        ('Add item to restaurant order', Icons.add_shopping_cart, 'Send menu items into kitchen queue'),
        ('Update restaurant kitchen', Icons.soup_kitchen, 'Move queued items to preparing, ready or served'),
        ('Restaurant payment', Icons.payments_outlined, 'Record full cash/card/bank payment for an open order'),
        ('Complete restaurant order', Icons.task_alt, 'Close only fully paid orders with kitchen items served/cancelled'),
        ('Vehicle purchase/sale', Icons.directions_car, 'Record purchase/sale transaction'),
        ('Vehicle profit report', Icons.account_balance_wallet_outlined, 'Sale proceeds minus purchase costs and recorded expenses'),
        ('Cargo status tracking', Icons.local_shipping, 'Record status, location and tracking history'),
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
