import 'package:flutter/material.dart';

import '../../services/db_service.dart';
import '../../services/snooker_club_service.dart';
import '../../services/snooker_report_service.dart';
import '../../utils/theme.dart';
import '../pos/pos_screen.dart';

class SnookerClubScreen extends StatefulWidget {
  const SnookerClubScreen({super.key});

  @override
  State<SnookerClubScreen> createState() => _SnookerClubScreenState();
}

class _SnookerClubScreenState extends State<SnookerClubScreen> {
  final _service = SnookerClubService.instance;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, Object?>> _tables = [];
  List<Map<String, Object?>> _games = [];
  List<Map<String, Object?>> _payments = [];
  List<Map<String, Object?>> _expenses = [];
  List<Map<String, Object?>> _sessions = [];
  List<Map<String, Object?>> _equipment = [];
  List<Map<String, Object?>> _inventory = [];
  List<Map<String, Object?>> _equipmentMovements = [];
  Map<String, Object?> _report = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await _service.ensureInitialTables(minimumTables: 9);
      final values = await Future.wait<Object>([
        _service.tables(),
        _service.games(),
        _service.recentPayments(),
        _service.expenses(),
        _service.cashSessions(),
        _service.dailyReport(),
        _service.equipmentAssets(),
        _service.inventoryItems(),
        _service.equipmentMovements(),
      ]);
      if (!mounted) return;
      setState(() {
        _tables = (values[0] as List).cast<Map<String, Object?>>();
        _games = (values[1] as List).cast<Map<String, Object?>>();
        _payments = (values[2] as List).cast<Map<String, Object?>>();
        _expenses = (values[3] as List).cast<Map<String, Object?>>();
        _sessions = (values[4] as List).cast<Map<String, Object?>>();
        _report = values[5] as Map<String, Object?>;
        _equipment = (values[6] as List).cast<Map<String, Object?>>();
        _inventory = (values[7] as List).cast<Map<String, Object?>>();
        _equipmentMovements = (values[8] as List).cast<Map<String, Object?>>();
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    }
  }

  String get _actor => DBService.instance.activeUserId ?? 'local-user';
  String _money(Object? value) => 'Rs. ${((value as num?)?.toDouble() ?? 0).toStringAsFixed(2)}';
  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, String>?> _form(String title, List<String> labels, {Map<String, String> initial = const {}}) async {
    final controllers = <String, TextEditingController>{
      for (final label in labels) label: TextEditingController(text: initial[label] ?? ''),
    };
    String? errorText;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final label in labels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controllers[label],
                      keyboardType: label.toLowerCase().contains('fee') ||
                              label.toLowerCase().contains('amount') ||
                              label.toLowerCase().contains('discount') ||
                              label.toLowerCase().contains('cash')
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
                    ),
                  ),
                if (errorText != null)
                  Align(alignment: Alignment.centerLeft, child: Text(errorText!, style: const TextStyle(color: Colors.red))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final values = {for (final e in controllers.entries) e.key: e.value.text.trim()};
                if (values.values.any((v) => v.isEmpty)) {
                  setDialogState(() => errorText = 'Please fill in every field.');
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

  Future<String?> _chooseWinner(Map<String, Object?> game) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select winner'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(game['playerAName']?.toString() ?? 'Player A'), onTap: () => Navigator.pop(dialogContext, game['playerAId']?.toString())),
            ListTile(title: Text(game['playerBName']?.toString() ?? 'Player B'), onTap: () => Navigator.pop(dialogContext, game['playerBId']?.toString())),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _startGame(Map<String, Object?> table) async {
    final defaultFee = await _service.defaultGameFee();
    final values = await _form('Start ${table['name']}', ['Player A name', 'Player B name', 'Game fee (Rs.)', 'Discount (Rs.)'], initial: {
      'Game fee (Rs.)': defaultFee.toStringAsFixed(2),
      'Discount (Rs.)': '0',
    });
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.startGame(
        tableId: table['id']! as String,
        playerA: values['Player A name']!,
        playerB: values['Player B name']!,
        feeAmount: double.parse(values['Game fee (Rs.)']!),
        discountAmount: double.parse(values['Discount (Rs.)']!),
        actorId: _actor,
      );
      _message('Game started.');
    });
  }

  Future<void> _setDefaultFee() async {
    final current = await _service.defaultGameFee();
    final values = await _form('Default fee per game', ['Game fee (Rs.)'], initial: {'Game fee (Rs.)': current.toStringAsFixed(2)});
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.setDefaultGameFee(double.parse(values['Game fee (Rs.)']!));
      _message('Default game fee saved.');
    });
  }

  Future<void> _complete(Map<String, Object?> game) async {
    final winnerId = await _chooseWinner(game);
    if (winnerId == null || !mounted) return;
    await _perform(() async {
      await _service.completeGame(gameId: game['id']! as String, winnerId: winnerId, actorId: _actor);
      _message('Game completed. Record the fee payment when received.');
    });
  }

  Future<void> _cancel(Map<String, Object?> game) async {
    final values = await _form('Cancel game', ['Cancellation reason']);
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.cancelGame(gameId: game['id']! as String, reason: values['Cancellation reason']!, actorId: _actor);
      _message('Game cancelled and table released.');
    });
  }

  Future<void> _takePayment(Map<String, Object?> game) async {
    final fee = ((game['finalAmount'] as num?)?.toDouble() ?? 0);
    final paid = ((game['netPaid'] as num?)?.toDouble() ?? 0);
    final remaining = (fee - paid).clamp(0, double.infinity).toDouble();
    if (remaining <= 0) {
      _message('This game has no outstanding fee.');
      return;
    }
    final loserId = game['winnerId'] == game['playerAId'] ? game['playerBId']! as String : game['playerAId']! as String;
    final loserName = game['winnerId'] == game['playerAId'] ? game['playerBName'] : game['playerAName'];
    final values = await _form('Collect game fee from $loserName', ['Amount (Rs.)', 'Payment method (cash/bank/card/wallet/other)', 'Reference (enter NONE if unavailable)'], initial: {
      'Amount (Rs.)': remaining.toStringAsFixed(2),
      'Payment method (cash/bank/card/wallet/other)': 'cash',
      'Reference (enter NONE if unavailable)': 'NONE',
    });
    if (values == null || !mounted) return;
    final reference = values['Reference (enter NONE if unavailable)'] == 'NONE' ? null : values['Reference (enter NONE if unavailable)'];
    await _perform(() async {
      await _service.recordPayment(
        gameId: game['id']! as String,
        amount: double.parse(values['Amount (Rs.)']!),
        method: values['Payment method (cash/bank/card/wallet/other)']!,
        payerId: loserId,
        reference: reference,
        idempotencyKey: reference == null ? null : 'payment:${values['Payment method (cash/bank/card/wallet/other)']}:$reference',
        actorId: _actor,
      );
      _message('Payment saved.');
    });
  }

  Future<void> _refund(Map<String, Object?> payment) async {
    final values = await _form('Refund game payment', ['Refund amount (Rs.)', 'Refund method (cash/bank/card/wallet/other)', 'Reason']);
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.refundPayment(
        gameId: payment['gameId']! as String,
        amount: double.parse(values['Refund amount (Rs.)']!),
        method: values['Refund method (cash/bank/card/wallet/other)']!,
        reason: values['Reason']!,
        actorId: _actor,
      );
      _message('Refund recorded.');
    });
  }

  Future<void> _addExpense() async {
    final values = await _form('Add club expense', ['Category', 'Amount (Rs.)', 'Payment method (cash/bank/card/wallet/other)', 'Note']);
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.addExpense(
        category: values['Category']!,
        amount: double.parse(values['Amount (Rs.)']!),
        paymentMethod: values['Payment method (cash/bank/card/wallet/other)']!,
        note: values['Note'],
        actorId: _actor,
      );
      _message('Expense saved.');
    });
  }

  Future<void> _cashSessionAction() async {
    final open = _sessions.where((s) => s['closedAt'] == null).toList();
    if (open.isEmpty) {
      final values = await _form('Open daily cash session', ['Opening cash (Rs.)']);
      if (values == null || !mounted) return;
      await _perform(() async {
        await _service.openCashSession(openingCash: double.parse(values['Opening cash (Rs.)']!), actorId: _actor);
        _message('Cash session opened.');
      });
    } else {
      final values = await _form('Close daily cash session', ['Actual closing cash (Rs.)']);
      if (values == null || !mounted) return;
      await _perform(() async {
        await _service.closeCashSession(
          sessionId: open.first['id']! as String,
          actualClosingCash: double.parse(values['Actual closing cash (Rs.)']!),
          actorId: _actor,
        );
        _message('Cash session closed. Check the variance in the session history.');
      });
    }
  }

  Future<void> _openRefreshmentsPos() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PosScreen()));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Snooker Club'),
        actions: [
          IconButton(tooltip: 'Set default game fee', onPressed: _setDefaultFee, icon: const Icon(Icons.price_change_outlined)),
          IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.table_bar_outlined), text: 'Tables'),
            Tab(icon: Icon(Icons.sports_esports_outlined), text: 'Games'),
            Tab(icon: Icon(Icons.payments_outlined), text: 'Accounts'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Reports'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Equipment & Stock'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), const SizedBox(height: 12), FilledButton(onPressed: _reload, child: const Text('Retry'))])))
              : TabBarView(children: [
                  _buildTables(),
                  _buildGames(),
                  _buildAccounts(),
                  _buildReports(),
                  _buildEquipment(),
                ]),
      floatingActionButton: _busy ? const FloatingActionButton(onPressed: null, child: CircularProgressIndicator()) : null,
    ));
  }

  Widget _buildTables() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard('Table management', '${_tables.length} tables • one active game per table', Icons.table_bar_rounded),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => _perform(() async { await _service.addTable(); _message('Table added.'); }), icon: const Icon(Icons.add), label: const Text('Add another table')),
          const SizedBox(height: 8),
          for (final table in _tables) Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: table['status'] == 'occupied' ? Colors.orange.shade100 : table['status'] == 'maintenance' ? Colors.red.shade100 : Colors.teal.shade50,
                child: Icon(Icons.table_bar, color: table['status'] == 'occupied' ? Colors.deepOrange : table['status'] == 'maintenance' ? Colors.red : Colors.teal),
              ),
              title: Text(table['name']?.toString() ?? 'Table'),
              subtitle: Text((table['status'] ?? 'available').toString().toUpperCase()),
              trailing: table['status'] == 'available'
                  ? Wrap(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'Start game', onPressed: () => _startGame(table), icon: const Icon(Icons.play_arrow_rounded)),
                      IconButton(tooltip: 'Maintenance', onPressed: () => _perform(() => _service.setTableMaintenance(table['id']! as String, true)), icon: const Icon(Icons.build_outlined)),
                    ])
                  : table['status'] == 'maintenance'
                      ? IconButton(tooltip: 'Mark available', onPressed: () => _perform(() => _service.setTableMaintenance(table['id']! as String, false)), icon: const Icon(Icons.check_circle_outline))
                      : const Icon(Icons.sports_esports_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGames() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard('Game history', 'Players, winner, fee and payment status', Icons.sports_esports_rounded),
          const SizedBox(height: 10),
          if (_games.isEmpty) const _EmptyState('No games yet. Start a game from the Tables tab.'),
          for (final game in _games) Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${game['tableName'] ?? 'Table'} • ${game['status']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text(_money(game['finalAmount']), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0B3D91))),
                ]),
                const SizedBox(height: 8),
                Text('${game['playerAName']}  vs  ${game['playerBName']}'),
                if (game['winnerId'] != null) Text('Winner: ${game['winnerId'] == game['playerAId'] ? game['playerAName'] : game['playerBName']}'),
                if (game['winnerId'] != null) Text('Fee payer (loser): ${game['winnerId'] == game['playerAId'] ? game['playerBName'] : game['playerAName']}'),
                Text('Paid: ${_money(game['netPaid'])} • Due: ${_money((((game['finalAmount'] as num?)?.toDouble() ?? 0) - ((game['netPaid'] as num?)?.toDouble() ?? 0)).clamp(0, double.infinity))}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  if (game['status'] == 'active') FilledButton.tonal(onPressed: () => _complete(game), child: const Text('Complete')),
                  if (game['status'] == 'active') OutlinedButton(onPressed: () => _cancel(game), child: const Text('Cancel game')),
                  if (game['status'] == 'completed' && (((game['finalAmount'] as num?)?.toDouble() ?? 0) > ((game['netPaid'] as num?)?.toDouble() ?? 0))) FilledButton(onPressed: () => _takePayment(game), child: const Text('Collect fee')),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccounts() {
    final openSession = _sessions.any((s) => s['closedAt'] == null);
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard('Payments & expenses', 'Game fees stay separate from refreshments POS sales', Icons.account_balance_wallet_outlined),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _addExpense, icon: const Icon(Icons.remove_circle_outline), label: const Text('Add expense')),
            FilledButton.tonalIcon(onPressed: _cashSessionAction, icon: Icon(openSession ? Icons.lock_clock : Icons.point_of_sale_outlined), label: Text(openSession ? 'Close cash' : 'Open cash')),
            OutlinedButton.icon(onPressed: _openRefreshmentsPos, icon: const Icon(Icons.local_cafe_outlined), label: const Text('Refreshments POS')),
          ]),
          const SizedBox(height: 16),
          const Text('Recent payments and refunds', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (_payments.isEmpty) const _EmptyState('No payments recorded yet.'),
          for (final payment in _payments) Card(
            child: ListTile(
              leading: Icon(payment['type'] == 'refund' ? Icons.undo : Icons.payments_outlined, color: payment['type'] == 'refund' ? Colors.red : Colors.teal),
              title: Text('${payment['type']} • ${_money(payment['amount'])}'),
              subtitle: Text('${payment['payerName'] == null ? 'Club' : 'Paid by ${payment['payerName']}'} • Game ${payment['gameId']} • ${payment['method']} • ${payment['receivedAt']}'),
              trailing: payment['type'] == 'payment' ? IconButton(tooltip: 'Refund', onPressed: () => _refund(payment), icon: const Icon(Icons.reply)) : null,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Expenses', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (_expenses.isEmpty) const _EmptyState('No club expenses recorded.'),
          for (final expense in _expenses) ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(expense['category']?.toString() ?? 'Expense'),
            subtitle: Text('${expense['occurredAt']} • ${expense['paymentMethod']}'),
            trailing: Text(_money(expense['amount'])),
          ),
          const SizedBox(height: 12),
          const Text('Cash sessions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (_sessions.isEmpty) const _EmptyState('Open a cash session to track opening and closing cash.'),
          for (final session in _sessions) ListTile(
            leading: Icon(session['closedAt'] == null ? Icons.lock_open_outlined : Icons.lock_outline),
            title: Text(session['closedAt'] == null ? 'Open session' : 'Closed session'),
            subtitle: Text('Opening ${_money(session['openingCash'])} • Expected ${_money(session['expectedClosingCash'])} • Actual ${_money(session['actualClosingCash'])}'),
            trailing: session['difference'] == null ? null : Text(_money(session['difference']), style: TextStyle(color: ((session['difference'] as num).abs() > 0.009) ? Colors.red : Colors.green)),
          ),
        ],
      ),
    );
  }


  Future<void> _addAsset(String type) async {
    final title = type == 'cue' ? 'Register cue' : type == 'ball_set' ? 'Register ball set' : 'Register locker';
    final values = await _form(title, ['Asset number / code', 'Name / description']);
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.addEquipmentAsset(
        assetType: type,
        assetNumber: values['Asset number / code']!,
        name: values['Name / description']!,
        actorId: _actor,
      );
      _message('$title saved.');
    });
  }

  Future<void> _addInventory() async {
    final values = await _form('Add consumable stock', ['Item name', 'Category (chalk/tip/glove/other)', 'Unit (piece/box)', 'Opening quantity', 'Minimum stock warning']);
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.addInventoryItem(
        name: values['Item name']!,
        category: values['Category (chalk/tip/glove/other)']!.toLowerCase(),
        unit: values['Unit (piece/box)']!,
        openingQuantity: double.parse(values['Opening quantity']!),
        minimumQuantity: double.parse(values['Minimum stock warning']!),
        actorId: _actor,
      );
      _message('Stock item added.');
    });
  }

  Future<void> _adjustStock(Map<String, Object?> item, String movement) async {
    final label = movement == 'purchase' ? 'Purchase quantity to add' : movement == 'consume' ? 'Quantity used' : movement == 'damage' ? 'Damaged quantity' : 'Quantity adjustment (+/-)';
    final values = await _form(label, ['Quantity', 'Note']);
    if (values == null || !mounted) return;
    final amount = double.parse(values['Quantity']!);
    await _perform(() async {
      await _service.adjustInventory(
        itemId: item['id']! as String,
        quantityChange: movement == 'purchase' ? amount : movement == 'adjustment' ? amount : -amount,
        movementType: movement,
        note: values['Note'],
        actorId: _actor,
      );
      _message('Stock movement saved.');
    });
  }

  Future<void> _assignAsset(Map<String, Object?> asset) async {
    final values = await _form('Issue ${asset['name']}', ['Player / staff name']);
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.assignEquipment(assetId: asset['id']! as String, personName: values['Player / staff name']!, actorId: _actor);
      _message('Equipment issued to ${values['Player / staff name']}.');
    });
  }

  Future<void> _markAsset(Map<String, Object?> asset, String status) async {
    final values = await _form(status == 'repair' ? 'Send to repair' : status == 'missing' ? 'Mark missing' : status == 'retired' ? 'Retire equipment' : 'Mark available', ['Reason / note']);
    if (values == null || !mounted) return;
    await _perform(() async {
      await _service.setEquipmentStatus(assetId: asset['id']! as String, status: status, note: values['Reason / note'], actorId: _actor);
      _message('Equipment status updated.');
    });
  }

  Widget _buildEquipment() {
    final cues = _equipment.where((e) => e['assetType'] == 'cue').toList();
    final balls = _equipment.where((e) => e['assetType'] == 'ball_set').toList();
    final lockers = _equipment.where((e) => e['assetType'] == 'locker').toList();
    int countStatus(List<Map<String, Object?>> rows, String status) => rows.where((e) => e['status'] == status).length;
    final lowStock = _inventory.where((i) => ((i['quantity'] as num?)?.toDouble() ?? 0) <= ((i['minimumQuantity'] as num?)?.toDouble() ?? 0)).toList();
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard('Equipment & stock register', 'Track cues, ball sets, lockers, chalk and who holds each item', Icons.inventory_2_outlined),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _equipmentMetric('Cues', '${cues.length}', '${countStatus(cues, 'available')} available'),
              _equipmentMetric('Ball sets', '${balls.length}', '${countStatus(balls, 'available')} available'),
              _equipmentMetric('Lockers', '${lockers.length}', '${countStatus(lockers, 'available')} available'),
              _equipmentMetric('Low stock', '${lowStock.length}', 'items at/below minimum'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(onPressed: () => _addAsset('cue'), icon: const Icon(Icons.add), label: const Text('Add cue')),
            FilledButton.tonalIcon(onPressed: () => _addAsset('ball_set'), icon: const Icon(Icons.add), label: const Text('Add ball set')),
            FilledButton.tonalIcon(onPressed: () => _addAsset('locker'), icon: const Icon(Icons.add), label: const Text('Add locker')),
            OutlinedButton.icon(onPressed: _addInventory, icon: const Icon(Icons.add_box_outlined), label: const Text('Add stock item')),
          ]),
          const SizedBox(height: 16),
          const Text('Cues, ball sets and lockers', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (_equipment.isEmpty) const _EmptyState('Register your existing cues, ball sets and lockers to establish opening counts.'),
          for (final asset in _equipment) Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(asset['assetType'] == 'cue' ? Icons.sports_esports_outlined : asset['assetType'] == 'ball_set' ? Icons.circle_outlined : Icons.lock_outline)),
              title: Text('${asset['name']} • #${asset['assetNumber']}'),
              subtitle: Text('${asset['assetType']} • ${asset['status']}${asset['assignedToName'] == null ? '' : ' • With: ${asset['assignedToName']}'}${asset['tableName'] == null ? '' : ' • ${asset['tableName']}'}${asset['lockerNumber'] == null ? '' : ' • Locker ${asset['lockerNumber']}'}'),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'issue') _assignAsset(asset);
                  if (action == 'return') _perform(() => _service.returnEquipment(assetId: asset['id']! as String, actorId: _actor));
                  if (action == 'repair' || action == 'missing' || action == 'retired' || action == 'available') _markAsset(asset, action);
                },
                itemBuilder: (_) => [
                  if (asset['status'] == 'available') const PopupMenuItem(value: 'issue', child: Text('Issue to player/staff')),
                  if (asset['status'] == 'in_use') const PopupMenuItem(value: 'return', child: Text('Return to club')),
                  if (asset['status'] != 'repair' && asset['status'] != 'retired') const PopupMenuItem(value: 'repair', child: Text('Send to repair')),
                  if (asset['status'] != 'missing' && asset['status'] != 'retired') const PopupMenuItem(value: 'missing', child: Text('Mark missing')),
                  if (asset['status'] != 'retired') const PopupMenuItem(value: 'retired', child: Text('Retire')),
                  if (asset['status'] == 'repair' || asset['status'] == 'missing') const PopupMenuItem(value: 'available', child: Text('Mark available')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Consumables', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (_inventory.isEmpty) const _EmptyState('Add chalk, tips, gloves and other consumables with opening stock.'),
          for (final item in _inventory) Card(
            child: ListTile(
              leading: Icon(Icons.inventory_2_outlined, color: ((item['quantity'] as num?)?.toDouble() ?? 0) <= ((item['minimumQuantity'] as num?)?.toDouble() ?? 0) ? Colors.red : Colors.teal),
              title: Text('${item['name']} • ${item['category']}'),
              subtitle: Text('Minimum: ${item['minimumQuantity']} ${item['unit']} • ${((item['quantity'] as num?)?.toDouble() ?? 0) <= ((item['minimumQuantity'] as num?)?.toDouble() ?? 0) ? 'LOW STOCK' : 'In stock'}'),
              trailing: SizedBox(width: 150, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${item['quantity']} ${item['unit']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  onSelected: (value) => _adjustStock(item, value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'purchase', child: Text('Record purchase')),
                    PopupMenuItem(value: 'consume', child: Text('Record used')),
                    PopupMenuItem(value: 'damage', child: Text('Record damaged')),
                    PopupMenuItem(value: 'adjustment', child: Text('Stock adjustment')),
                  ],
                ),
              ])),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Recent equipment activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (_equipmentMovements.isEmpty) const _EmptyState('Issues, returns, purchases and stock adjustments will be listed here.'),
          for (final move in _equipmentMovements.take(30)) ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: Text('${move['assetNumber'] ?? move['inventoryName'] ?? 'Equipment'} • ${move['movementType']}'),
            subtitle: Text('${move['occurredAt']} • ${move['personName'] ?? move['note'] ?? ''}'),
            trailing: Text('${move['quantity']}'),
          ),
        ],
      ),
    );
  }

  Widget _equipmentMetric(String title, String value, String subtitle) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(title, style: const TextStyle(fontSize: 12)),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0B3D91))),
        Text(subtitle, style: const TextStyle(fontSize: 10)),
      ]),
    ),
  );

  Widget _buildReports() {
    final wins = (_report['playerWins'] as List? ?? const []).cast<Map<String, Object?>>();
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard('Daily club report', 'Daily income, stock cost, outstanding fees and cash reconciliation', Icons.analytics_outlined),
          const SizedBox(height: 12),
          _metric('Completed games', '${_report['completedGames'] ?? 0}', Icons.sports_esports_outlined),
          _metric('Game fees earned', _money(_report['gameFeesEarned']), Icons.payments_outlined),
          _metric('Payments received', _money(_report['paymentsReceived']), Icons.account_balance_wallet_outlined),
          _metric('Outstanding game fees', _money(_report['outstandingGameFees']), Icons.pending_actions_outlined),
          _metric('Refreshment sales', _money(_report['refreshmentSales']), Icons.local_cafe_outlined),
          _metric('Refreshment cost', _money(_report['refreshmentCost']), Icons.inventory_2_outlined),
          _metric('Club expenses', _money(_report['snookerExpenses']), Icons.receipt_long_outlined),
          _metric('Operating result before other costs', _money(_report['operatingResultBeforeOtherCosts']), Icons.trending_up_outlined),
          const SizedBox(height: 14),
          const Text('Player wins', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (wins.isEmpty) const _EmptyState('Player results will appear after completed games.'),
          for (final win in wins) ListTile(leading: const Icon(Icons.emoji_events_outlined, color: Color(0xFFFFBF24)), title: Text(win['name']?.toString() ?? ''), trailing: Text('${win['wins']} wins')),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () async { try { await SnookerReportService.shareDailyReport(_report); } catch (e) { _message('Could not share report: $e'); } }, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Share daily PDF')),
          OutlinedButton.icon(onPressed: () async { try { await SnookerReportService.printDailyReport(_report); } catch (e) { _message('Could not print report: $e'); } }, icon: const Icon(Icons.print_outlined), label: const Text('Print report')),
          const SizedBox(height: 8),
          const Text('Refreshment sales use the existing POS sales ledger. Final business profit must also account for all applicable operating costs and accounting adjustments.', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
        ],
      ),
    );
  }

  Widget _heroCard(String title, String subtitle, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: const LinearGradient(colors: [Color(0xFF0B3D91), Color(0xFF082B4C)]),
    ),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF14B8A6), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Colors.white)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Color(0xFFDCE8FF), fontSize: 12)),
      ])),
    ]),
  );

  Widget _metric(String title, String value, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon, color: const Color(0xFF0B3D91)),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0B3D91))),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}
