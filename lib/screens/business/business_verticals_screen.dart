import 'package:flutter/material.dart';
import '../../services/business_operations_service.dart';
import '../../services/db_service.dart';

class BusinessVerticalsScreen extends StatefulWidget {
  const BusinessVerticalsScreen({super.key});

  @override
  State<BusinessVerticalsScreen> createState() => _BusinessVerticalsScreenState();
}

class _BusinessVerticalsScreenState extends State<BusinessVerticalsScreen> with SingleTickerProviderStateMixin {
  final _ops = BusinessOperationsService.instance;
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  Map<String, List<Map<String, Object?>>> _rows = {};
  Map<String, Object?> _report = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final db = await DBService.instance.database;
      final results = await Future.wait([
        db.query('school_students', orderBy: 'admissionDate DESC'),
        db.query('school_fees', orderBy: 'dueDate DESC'),
        db.query('clinic_patients', orderBy: 'name COLLATE NOCASE'),
        db.query('clinic_appointments', orderBy: 'appointmentAt DESC'),
        db.query('salon_services', orderBy: 'name COLLATE NOCASE'),
        db.query('salon_bookings', orderBy: 'bookingAt DESC'),
        db.query('farm_plots', orderBy: 'name COLLATE NOCASE'),
        db.query('farm_activities', orderBy: 'activityDate DESC'),
        db.query('construction_projects', orderBy: 'name COLLATE NOCASE'),
        db.query('construction_tasks', orderBy: 'dueDate ASC'),
        db.query('public_service_cases', orderBy: 'openedAt DESC'),
      ]);
      final report = await _ops.businessVerticalReport();
      if (!mounted) return;
      setState(() {
        _rows = {
          'students': results[0], 'schoolFees': results[1],
          'patients': results[2], 'clinicAppointments': results[3],
          'salonServices': results[4], 'salonBookings': results[5],
          'farmPlots': results[6], 'farmActivities': results[7],
          'projects': results[8], 'tasks': results[9], 'cases': results[10],
        };
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  double _number(Object? value) => value is num ? value.toDouble() : 0;
  String _money(Object? value) => 'Rs. ${_number(value).toStringAsFixed(2)}';

  Future<void> _addCurrentRecord() async {
    final fieldsByTab = <int, List<(String, String)>>{
      0: [('Student name', 'required'), ('Guardian name', 'text'), ('Phone', 'text'), ('Class', 'text')],
      1: [('Patient name', 'required'), ('Phone', 'text'), ('Date of birth', 'text'), ('Notes', 'text')],
      2: [('Service name', 'required'), ('Duration minutes', 'required_number'), ('Price (Rs.)', 'required_number')],
      3: [('Plot name', 'required'), ('Area (acre)', 'required_number'), ('Crop', 'required'), ('Season', 'text')],
      4: [('Project name', 'required'), ('Client name', 'text'), ('Location', 'text'), ('Budget (Rs.)', 'required_number')],
      5: [('Case number', 'required'), ('Applicant name', 'required'), ('Service type', 'required'), ('Fee (Rs.)', 'required_number')],
    };
    const labels = ['student', 'patient', 'salon service', 'farm plot', 'construction project', 'public-service case'];
    final fields = fieldsByTab[_tabs.index]!;
    final controllers = <String, TextEditingController>{
      for (final field in fields) field.$1: TextEditingController(),
    };
    String? validationError;
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add ${labels[_tabs.index]}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controllers[field.$1],
                      keyboardType: field.$2.contains('number')
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(labelText: field.$1),
                    ),
                  ),
                if (validationError != null)
                  Text(validationError!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final v = {for (final e in controllers.entries) e.key: e.value.text.trim()};
                final missing = fields.where((f) => f.$2.startsWith('required') && (v[f.$1] ?? '').isEmpty);
                final invalidNumber = fields.where((f) => f.$2.contains('number') &&
                    double.tryParse(v[f.$1] ?? '') == null);
                if (missing.isNotEmpty || invalidNumber.isNotEmpty) {
                  setDialogState(() => validationError = missing.isNotEmpty
                      ? '${missing.first.$1} is required.'
                      : 'Enter a valid number for ${invalidNumber.first.$1}.');
                  return;
                }
                Navigator.pop(dialogContext, v);
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
    if (values == null || !mounted) return;
    double number(String key) => double.parse(values[key]!);
    try {
      switch (_tabs.index) {
        case 0:
          await _ops.addSchoolStudent(
            name: values['Student name']!,
            guardianName: values['Guardian name'],
            phone: values['Phone'],
            className: values['Class'],
          );
          break;
        case 1:
          await _ops.addClinicPatient(
            name: values['Patient name']!,
            phone: values['Phone'],
            dateOfBirth: values['Date of birth'],
            notes: values['Notes'],
          );
          break;
        case 2:
          await _ops.addSalonService(
            name: values['Service name']!,
            durationMinutes: number('Duration minutes').toInt(),
            price: number('Price (Rs.)'),
          );
          break;
        case 3:
          await _ops.addFarmPlot(
            name: values['Plot name']!,
            area: number('Area (acre)'),
            crop: values['Crop']!,
            season: values['Season'],
          );
          break;
        case 4:
          await _ops.addConstructionProject(
            name: values['Project name']!,
            clientName: values['Client name'],
            location: values['Location'],
            budget: number('Budget (Rs.)'),
          );
          break;
        case 5:
          await _ops.addPublicServiceCase(
            caseNumber: values['Case number']!,
            applicantName: values['Applicant name']!,
            serviceType: values['Service type']!,
            fee: number('Fee (Rs.)'),
          );
          break;
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${labels[_tabs.index]} saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save record: $e')),
      );
    }
  }

  Future<void> _showAddMenu() async {
    final index = _tabs.index;
    final options = switch (index) {
      0 => const [('primary', 'Add student'), ('related', 'Add fee record')],
      1 => const [('primary', 'Add patient'), ('related', 'Book appointment')],
      2 => const [('primary', 'Add salon service'), ('related', 'Book appointment')],
      3 => const [('primary', 'Add farm plot'), ('related', 'Record farm activity')],
      4 => const [('primary', 'Add project'), ('related', 'Add project task')],
      _ => const [('primary', 'Add service case')],
    };
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('What would you like to add?'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option.$1),
              child: Text(option.$2),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'related') {
      await _addRelatedRecord(index);
    } else {
      await _addCurrentRecord();
    }
  }

  /// Adds operational records linked to their parent record. The primary
  /// record alone is not enough for these verticals to complete real workflows.
  Future<void> _addRelatedRecord(int tabIndex) async {
    final parentRows = switch (tabIndex) {
      0 => _rows['students'] ?? <Map<String, Object?>>[],
      1 => _rows['patients'] ?? <Map<String, Object?>>[],
      2 => _rows['salonServices'] ?? <Map<String, Object?>>[],
      3 => _rows['farmPlots'] ?? <Map<String, Object?>>[],
      4 => _rows['projects'] ?? <Map<String, Object?>>[],
      _ => <Map<String, Object?>>[],
    };
    if (tabIndex != 2 && parentRows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create the parent record first, then add this workflow record.')),
        );
      }
      return;
    }

    final fieldsByTab = <int, List<(String, String)>>{
      0: [('Amount (Rs.)', 'required_number'), ('Note', 'text')],
      1: [('Appointment date/time', 'required'), ('Clinician', 'text'), ('Reason', 'text'), ('Fee (Rs.)', 'required_number')],
      2: [('Customer name', 'required'), ('Phone', 'text'), ('Booking date/time', 'required'), ('Staff name', 'text'), ('Amount (Rs.)', 'required_number')],
      3: [('Activity type', 'required'), ('Input name', 'text'), ('Quantity', 'required_number'), ('Cost (Rs.)', 'required_number'), ('Notes', 'text')],
      4: [('Task title', 'required'), ('Assigned to', 'text'), ('Due date', 'text'), ('Cost (Rs.)', 'required_number')],
    };
    final fields = fieldsByTab[tabIndex];
    if (fields == null) return;
    final controllers = <String, TextEditingController>{
      for (final field in fields) field.$1: TextEditingController(),
    };
    final parentRequired = tabIndex != 2;
    String? selectedParent = parentRows.isNotEmpty ? parentRows.first['id'] as String? : null;
    String? validationError;
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(switch (tabIndex) {
            0 => 'Add school fee',
            1 => 'Book clinic appointment',
            2 => 'Book salon appointment',
            3 => 'Record farm activity',
            _ => 'Add construction task',
          }),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (parentRows.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedParent,
                    decoration: InputDecoration(
                      labelText: switch (tabIndex) {
                        0 => 'Student',
                        1 => 'Patient',
                        2 => 'Service (optional)',
                        3 => 'Farm plot',
                        _ => 'Project',
                      },
                    ),
                    items: [
                      if (!parentRequired)
                        const DropdownMenuItem<String>(value: '', child: Text('No service selected')),
                      for (final row in parentRows)
                        DropdownMenuItem<String>(
                          value: row['id'] as String,
                          child: Text('${row['name'] ?? row['id']}'),
                        ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => selectedParent = value == '' ? null : value,
                    ),
                  ),
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: controllers[field.$1],
                      keyboardType: field.$2.contains('number')
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(labelText: field.$1),
                    ),
                  ),
                if (validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(validationError!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final entered = {
                  for (final entry in controllers.entries) entry.key: entry.value.text.trim(),
                };
                final missing = fields.where(
                  (field) => field.$2.startsWith('required') && (entered[field.$1] ?? '').isEmpty,
                );
                final invalidNumber = fields.where(
                  (field) => field.$2.contains('number') &&
                      (double.tryParse(entered[field.$1] ?? '') == null ||
                       double.parse(entered[field.$1]!) < 0),
                );
                if ((parentRequired && selectedParent == null) ||
                    missing.isNotEmpty || invalidNumber.isNotEmpty) {
                  setDialogState(() {
                    validationError = parentRequired && selectedParent == null
                        ? 'Select a parent record first.'
                        : missing.isNotEmpty
                            ? '${missing.first.$1} is required.'
                            : 'Enter a valid non-negative number for ${invalidNumber.first.$1}.';
                  });
                  return;
                }
                Navigator.pop(dialogContext, {...entered, '__parentId': selectedParent ?? ''});
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
    if (values == null || !mounted) return;

    double number(String key) => double.parse(values[key]!);
    try {
      switch (tabIndex) {
        case 0:
          await _ops.addSchoolFee(
            studentId: values['__parentId']!,
            amount: number('Amount (Rs.)'),
            note: values['Note'],
          );
          break;
        case 1:
          await _ops.bookClinicAppointment(
            patientId: values['__parentId']!,
            appointmentAt: values['Appointment date/time']!,
            clinician: values['Clinician'],
            reason: values['Reason'],
            fee: number('Fee (Rs.)'),
          );
          break;
        case 2:
          await _ops.bookSalonAppointment(
            customerName: values['Customer name']!,
            phone: values['Phone'],
            bookingAt: values['Booking date/time']!,
            serviceId: values['__parentId']!.isEmpty ? null : values['__parentId'],
            staffName: values['Staff name'],
            amount: number('Amount (Rs.)'),
          );
          break;
        case 3:
          await _ops.recordFarmActivity(
            plotId: values['__parentId']!,
            activityType: values['Activity type']!,
            inputName: values['Input name'],
            quantity: number('Quantity'),
            cost: number('Cost (Rs.)'),
            notes: values['Notes'],
          );
          break;
        case 4:
          await _ops.addConstructionTask(
            projectId: values['__parentId']!,
            title: values['Task title']!,
            assignedTo: values['Assigned to'],
            dueDate: values['Due date'],
            cost: number('Cost (Rs.)'),
          );
          break;
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workflow record saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save workflow record: $e')),
        );
      }
    }
  }

  Future<void> _recordSchoolPayment(Map<String, Object?> fee) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record school fee payment'),
        content: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Payment amount (Rs.)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () { final v = double.tryParse(controller.text); if (v != null) Navigator.pop(context, v); }, child: const Text('Record')),
        ],
      ),
    );
    controller.dispose();
    if (amount == null) return;
    try {
      await _ops.recordSchoolFeePayment(feeId: fee['id']! as String, amount: amount);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record payment: $e')));
    }
  }

  Future<void> _chooseStatus(String title, List<String> statuses, Future<void> Function(String) save) async {
    final status = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: statuses.map((s) => SimpleDialogOption(onPressed: () => Navigator.pop(context, s), child: Text(s.replaceAll('_', ' ')))).toList(),
      ),
    );
    if (status == null) return;
    try {
      await save(status);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Widget _recordList(List<Map<String, Object?>> rows, {required String empty, required Widget Function(Map<String, Object?>) tile}) {
    if (rows.isEmpty) return Center(child: Text(empty));
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => tile(rows[index]),
    );
  }

  Widget _summaryCards() {
    final school = _report['school'] as Map<String, Object?>? ?? {};
    final clinic = _report['clinic'] as Map<String, Object?>? ?? {};
    final salon = _report['salon'] as Map<String, Object?>? ?? {};
    final farm = _report['agriculture'] as Map<String, Object?>? ?? {};
    final construction = _report['construction'] as Map<String, Object?>? ?? {};
    final cases = _report['publicServices'] as Map<String, Object?>? ?? {};
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _metric('School fees outstanding', _money(school['outstanding'])),
      _metric('Clinic outstanding', _money(clinic['outstanding'])),
      _metric('Salon booked value', _money(salon['bookedValue'])),
      _metric('Farm activity cost', _money(farm['cost'])),
      _metric('Construction spent / budget', '${_money(construction['spent'])} / ${_money(construction['budget'])}'),
      _metric('Public-service fees', _money(cases['fees'])),
    ]);
  }

  Widget _metric(String title, String value) => SizedBox(
    width: 230,
    child: Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ]),
    )),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Business Modules & Reports'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [
        Tab(text: 'School'), Tab(text: 'Clinic'), Tab(text: 'Salon'),
        Tab(text: 'Agriculture'), Tab(text: 'Construction'), Tab(text: 'Public services'),
      ]),
    ),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _error != null ? Center(child: Text(_error!))
      : Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: _summaryCards()),
          Expanded(child: TabBarView(controller: _tabs, children: [
            _schoolTab(), _clinicTab(), _salonTab(), _farmTab(), _constructionTab(), _publicTab(),
          ])),
        ]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : _showAddMenu,
      icon: const Icon(Icons.add),
      label: const Text('Add workflow'),
    ),
  );

  Widget _schoolTab() => Column(children: [
    ListTile(title: const Text('Students'), subtitle: Text('${(_rows['students'] ?? []).length} enrolled')),
    Expanded(child: _recordList(_rows['students'] ?? [], empty: 'No students yet', tile: (r) => ListTile(
      leading: const Icon(Icons.school), title: Text('${r['name']}'),
      subtitle: Text('${r['className'] ?? 'No class'} · Guardian: ${r['guardianName'] ?? '—'}'),
    ))),
    const Divider(),
    ListTile(title: const Text('Fee ledger'), subtitle: Text('${(_rows['schoolFees'] ?? []).length} fee records')),
    Expanded(child: _recordList(_rows['schoolFees'] ?? [], empty: 'No fee records yet', tile: (r) => ListTile(
      title: Text('Student ${r['studentId']}'),
      subtitle: Text('Paid ${_money(r['paidAmount'])} / ${_money(r['amount'])} · ${r['status']}'),
      trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'pay') _recordSchoolPayment(r); }, itemBuilder: (_) => const [PopupMenuItem(value: 'pay', child: Text('Record payment'))]),
    ))),
  ]);

  Widget _clinicTab() => _recordList(_rows['clinicAppointments'] ?? [], empty: 'No clinic appointments yet', tile: (r) => ListTile(
    leading: const Icon(Icons.medical_services), title: Text('${r['appointmentAt']}'),
    subtitle: Text('Patient ${r['patientId']} · ${r['status']} · Paid ${_money(r['paidAmount'])}/${_money(r['fee'])}'),
    trailing: PopupMenuButton<String>(onSelected: (v) {
      if (v == 'payment') {
        _recordClinicPayment(r);
      } else {
        _chooseStatus(
          'Appointment status',
          ['scheduled', 'checked_in', 'completed', 'cancelled', 'no_show'],
          (s) => _ops.updateClinicAppointmentStatus(
            appointmentId: r['id']! as String,
            status: s,
          ),
        );
      }
    }, itemBuilder: (_) => const [PopupMenuItem(value: 'payment', child: Text('Record payment')), PopupMenuItem(value: 'status', child: Text('Change status'))]),
  ));

  Future<void> _recordClinicPayment(Map<String, Object?> appointment) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(context: context, builder: (context) => AlertDialog(
      title: const Text('Record clinic payment'),
      content: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (Rs.)')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () { final v = double.tryParse(controller.text); if (v != null) Navigator.pop(context, v); }, child: const Text('Record'))],
    ));
    controller.dispose();
    if (amount == null) return;
    try { await _ops.recordClinicPayment(appointmentId: appointment['id']! as String, amount: amount); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record payment: $e'))); }
  }

  Widget _salonTab() => _recordList(_rows['salonBookings'] ?? [], empty: 'No salon bookings yet', tile: (r) => ListTile(
    leading: const Icon(Icons.content_cut), title: Text('${r['customerName']} · ${r['bookingAt']}'),
    subtitle: Text('Service ${r['serviceId'] ?? '—'} · ${r['status']} · ${_money(r['amount'])}'),
    trailing: PopupMenuButton<String>(onSelected: (s) => _chooseStatus('Salon booking status', ['booked','in_progress','completed','cancelled','no_show'], (status) => _ops.updateSalonBookingStatus(bookingId: r['id']! as String, status: status)), itemBuilder: (_) => const [PopupMenuItem(value: 'status', child: Text('Change status'))]),
  ));

  Widget _farmTab() => _recordList(_rows['farmActivities'] ?? [], empty: 'No farm activities yet', tile: (r) => ListTile(
    leading: const Icon(Icons.agriculture), title: Text('${r['activityType']} · Plot ${r['plotId']}'),
    subtitle: Text('${r['activityDate']} · ${r['inputName'] ?? ''} · Qty ${r['quantity']}'),
    trailing: Text(_money(r['cost'])),
  ));

  Widget _constructionTab() => _recordList(_rows['tasks'] ?? [], empty: 'No construction tasks yet', tile: (r) => ListTile(
    leading: const Icon(Icons.construction), title: Text('${r['title']}'),
    subtitle: Text('Project ${r['projectId']} · ${r['status']} · ${_money(r['cost'])}'),
    trailing: PopupMenuButton<String>(onSelected: (s) => _chooseStatus('Task status', ['todo','in_progress','completed','cancelled'], (status) => _ops.updateConstructionTaskStatus(taskId: r['id']! as String, status: status)), itemBuilder: (_) => const [PopupMenuItem(value: 'status', child: Text('Change status'))]),
  ));

  Widget _publicTab() => _recordList(_rows['cases'] ?? [], empty: 'No public-service cases yet', tile: (r) => ListTile(
    leading: const Icon(Icons.account_balance), title: Text('${r['caseNumber']} · ${r['serviceType']}'),
    subtitle: Text('${r['applicantName']} · ${r['status']} · Fee ${_money(r['fee'])}'),
    trailing: PopupMenuButton<String>(onSelected: (s) => _chooseStatus('Case status', ['open','in_progress','resolved','rejected'], (status) => _ops.updatePublicServiceCaseStatus(caseId: r['id']! as String, status: status)), itemBuilder: (_) => const [PopupMenuItem(value: 'status', child: Text('Change status'))]),
  ));
}
