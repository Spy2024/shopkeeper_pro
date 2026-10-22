import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'db_service.dart';
import 'sync_queue_service.dart';

/// Offline-first operations for the Snooker Club business vertical.
/// All money is stored as numeric values in the club's local currency (PKR).
class SnookerClubService {
  SnookerClubService._();
  static final instance = SnookerClubService._();
  final Uuid _uuid = const Uuid();

  String _now() => DateTime.now().toIso8601String();

  Future<void> _queue(String operation, String table, String id, Map<String, Object?> row) async {
    try {
      await SyncQueueService.instance.queueOperation(
        operation: operation,
        tableName: table,
        documentId: id,
        data: Map<String, dynamic>.from(row),
      );
    } catch (error) {
      // The local transaction is authoritative while offline. Keep the
      // failure visible in logs; the durable queue is retried when configured.
      debugPrint('[SnookerClub] Could not enqueue $table/$id: $error');
    }
  }

  Future<void> ensureInitialTables({int minimumTables = 9}) async {
    if (minimumTables < 1) throw ArgumentError.value(minimumTables, 'minimumTables');
    final db = await DBService.instance.database;
    final existing = await db.query('snooker_tables', columns: ['id']);
    if (existing.length >= minimumTables) return;
    final created = <Map<String, Object?>>[];
    await db.transaction((txn) async {
      final rows = await txn.query('snooker_tables', columns: ['tableNumber']);
      var next = rows.fold<int>(0, (max, row) {
        final number = (row['tableNumber'] as num?)?.toInt() ?? 0;
        return number > max ? number : max;
      }) + 1;
      while (next <= minimumTables) {
        final now = _now();
        final row = <String, Object?>{
          'id': _uuid.v4(),
          'tableNumber': next,
          'name': 'Table $next',
          'status': 'available',
          'activeGameId': null,
          'createdAt': now,
          'updatedAt': now,
        };
        await txn.insert('snooker_tables', row, conflictAlgorithm: ConflictAlgorithm.ignore);
        created.add(row);
        next++;
      }
    });
    for (final row in created) {
      await _queue('create', 'snooker_tables', row['id']! as String, row);
    }
  }

  Future<List<Map<String, Object?>>> tables() async {
    await ensureInitialTables();
    return (await DBService.instance.database).query('snooker_tables', orderBy: 'tableNumber ASC');
  }

  Future<List<Map<String, Object?>>> players({String? query}) async {
    final db = await DBService.instance.database;
    final value = query?.trim();
    if (value == null || value.isEmpty) {
      return db.query('snooker_players', orderBy: 'name COLLATE NOCASE ASC');
    }
    return db.query(
      'snooker_players',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%$value%', '%$value%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<String> addTable({String? name}) async {
    final db = await DBService.instance.database;
    late Map<String, Object?> row;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('SELECT COALESCE(MAX(tableNumber), 0) AS maxNumber FROM snooker_tables');
      final number = ((rows.first['maxNumber'] as num?)?.toInt() ?? 0) + 1;
      final now = _now();
      row = {
        'id': _uuid.v4(),
        'tableNumber': number,
        'name': name?.trim().isNotEmpty == true ? name!.trim() : 'Table $number',
        'status': 'available',
        'activeGameId': null,
        'createdAt': now,
        'updatedAt': now,
      };
      await txn.insert('snooker_tables', row);
    });
    await _queue('create', 'snooker_tables', row['id']! as String, row);
    return row['id']! as String;
  }

  Future<void> setTableMaintenance(String tableId, bool maintenance) async {
    final db = await DBService.instance.database;
    late Map<String, Object?> row;
    await db.transaction((txn) async {
      final rows = await txn.query('snooker_tables', where: 'id = ?', whereArgs: [tableId], limit: 1);
      if (rows.isEmpty) throw StateError('Table not found.');
      if (rows.first['activeGameId'] != null) throw StateError('An active table cannot enter maintenance.');
      row = {...rows.first, 'status': maintenance ? 'maintenance' : 'available', 'updatedAt': _now()};
      await txn.update('snooker_tables', row, where: 'id = ?', whereArgs: [tableId]);
    });
    await _queue('update', 'snooker_tables', tableId, row);
  }

  Future<double> defaultGameFee() async {
    final db = await DBService.instance.database;
    final rows = await db.query('snooker_settings', where: 'key = ?', whereArgs: ['defaultGameFee'], limit: 1);
    return rows.isEmpty ? 0 : double.tryParse(rows.first['value']?.toString() ?? '') ?? 0;
  }

  Future<void> setDefaultGameFee(double amount) async {
    if (!amount.isFinite || amount < 0) throw ArgumentError('Game fee must be a non-negative amount.');
    final db = await DBService.instance.database;
    final row = {'id': 'defaultGameFee', 'key': 'defaultGameFee', 'value': amount.toStringAsFixed(2), 'updatedAt': _now()};
    await db.insert('snooker_settings', row, conflictAlgorithm: ConflictAlgorithm.replace);
    await _queue('update', 'snooker_settings', 'defaultGameFee', row);
  }

  Future<String> _playerInTransaction(Transaction txn, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Player name is required.');
    final normalized = cleanName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final found = await txn.query('snooker_players', where: 'normalizedName = ?', whereArgs: [normalized], limit: 1);
    if (found.isNotEmpty) return found.first['id']! as String;
    final id = _uuid.v4();
    final now = _now();
    await txn.insert('snooker_players', {
      'id': id, 'name': cleanName, 'normalizedName': normalized,
      'phone': null, 'notes': null, 'createdAt': now, 'updatedAt': now,
    });
    return id;
  }

  Future<String> startGame({
    required String tableId,
    required String playerA,
    required String playerB,
    required double feeAmount,
    double discountAmount = 0,
    String? actorId,
  }) async {
    if (playerA.trim().isEmpty || playerB.trim().isEmpty) throw ArgumentError('Both player names are required.');
    String normalizePlayerName(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizePlayerName(playerA) == normalizePlayerName(playerB)) {
      throw ArgumentError('Players must be different.');
    }
    if (!feeAmount.isFinite || feeAmount < 0 || !discountAmount.isFinite || discountAmount < 0 || discountAmount > feeAmount) {
      throw ArgumentError('Invalid game fee or discount.');
    }
    final db = await DBService.instance.database;
    final gameId = _uuid.v4();
    final feeId = _uuid.v4();
    final eventId = _uuid.v4();
    final now = _now();
    late Map<String, Object?> tableRow;
    late Map<String, Object?> gameRow;
    late Map<String, Object?> feeRow;
    late Map<String, Object?> eventRow;
    late Map<String, Object?> playerARow;
    late Map<String, Object?> playerBRow;
    await db.transaction((txn) async {
      final tables = await txn.query('snooker_tables', where: 'id = ?', whereArgs: [tableId], limit: 1);
      if (tables.isEmpty) throw StateError('Table not found.');
      if (tables.first['status'] != 'available' || tables.first['activeGameId'] != null) {
        throw StateError('This table is not available.');
      }
      final playerAId = await _playerInTransaction(txn, playerA);
      final playerBId = await _playerInTransaction(txn, playerB);
      final a = (await txn.query('snooker_players', where: 'id = ?', whereArgs: [playerAId], limit: 1)).single;
      final b = (await txn.query('snooker_players', where: 'id = ?', whereArgs: [playerBId], limit: 1)).single;
      playerARow = Map<String, Object?>.from(a);
      playerBRow = Map<String, Object?>.from(b);
      gameRow = {
        'id': gameId, 'tableId': tableId, 'playerAId': playerAId, 'playerBId': playerBId,
        'playerAName': a['name'], 'playerBName': b['name'], 'winnerId': null,
        'status': 'active', 'startedAt': now, 'endedAt': null, 'createdBy': actorId, 'updatedAt': now,
      };
      feeRow = {
        'id': feeId, 'gameId': gameId, 'feeAmount': feeAmount,
        'discountAmount': discountAmount, 'finalAmount': feeAmount - discountAmount, 'createdAt': now,
      };
      eventRow = {
        'id': eventId, 'gameId': gameId, 'eventType': 'started', 'previousValue': null,
        'newValue': 'active', 'reason': null, 'actorId': actorId, 'occurredAt': now,
        'idempotencyKey': 'event:$eventId',
      };
      tableRow = {...tables.first, 'status': 'occupied', 'activeGameId': gameId, 'updatedAt': now};
      await txn.insert('snooker_games', gameRow);
      await txn.insert('snooker_game_fees', feeRow);
      await txn.insert('snooker_game_events', eventRow);
      await txn.update('snooker_tables', tableRow, where: 'id = ?', whereArgs: [tableId]);
    });
    await _queue('create', 'snooker_players', playerARow['id']! as String, playerARow);
    await _queue('create', 'snooker_players', playerBRow['id']! as String, playerBRow);
    await _queue('create', 'snooker_games', gameId, gameRow);
    await _queue('create', 'snooker_game_fees', feeId, feeRow);
    await _queue('create', 'snooker_game_events', eventId, eventRow);
    await _queue('update', 'snooker_tables', tableId, tableRow);
    return gameId;
  }

  Future<void> completeGame({required String gameId, required String winnerId, String? actorId}) async {
    await _finishGame(gameId: gameId, status: 'completed', winnerId: winnerId, actorId: actorId);
  }

  Future<void> cancelGame({required String gameId, required String reason, String? actorId}) async {
    if (reason.trim().isEmpty) throw ArgumentError('A cancellation reason is required.');
    await _finishGame(gameId: gameId, status: 'cancelled', reason: reason.trim(), actorId: actorId);
  }

  Future<void> _finishGame({required String gameId, required String status, String? winnerId, String? reason, String? actorId}) async {
    final db = await DBService.instance.database;
    late Map<String, Object?> game;
    late Map<String, Object?> table;
    late Map<String, Object?> event;
    await db.transaction((txn) async {
      final games = await txn.query('snooker_games', where: 'id = ?', whereArgs: [gameId], limit: 1);
      if (games.isEmpty || games.first['status'] != 'active') throw StateError('Only an active game can be completed or cancelled.');
      game = Map<String, Object?>.from(games.first);
      if (status == 'completed' && winnerId != game['playerAId'] && winnerId != game['playerBId']) {
        throw ArgumentError('Winner must be one of the two players.');
      }
      final now = _now();
      game = {...game, 'status': status, 'winnerId': winnerId, 'endedAt': now, 'updatedAt': now};
      final tables = await txn.query('snooker_tables', where: 'id = ?', whereArgs: [game['tableId']], limit: 1);
      if (tables.isEmpty || tables.first['activeGameId'] != gameId) throw StateError('Table/game state mismatch; no changes saved.');
      table = {...tables.first, 'status': 'available', 'activeGameId': null, 'updatedAt': now};
      event = {
        'id': _uuid.v4(), 'gameId': gameId, 'eventType': status,
        'previousValue': 'active', 'newValue': status, 'reason': reason,
        'actorId': actorId, 'occurredAt': now, 'idempotencyKey': 'event:${_uuid.v4()}',
      };
      await txn.update('snooker_games', game, where: 'id = ?', whereArgs: [gameId]);
      await txn.update('snooker_tables', table, where: 'id = ?', whereArgs: [game['tableId']]);
      await txn.insert('snooker_game_events', event);
    });
    await _queue('update', 'snooker_games', gameId, game);
    await _queue('update', 'snooker_tables', table['id']! as String, table);
    await _queue('create', 'snooker_game_events', event['id']! as String, event);
  }

  Future<void> correctResult({required String gameId, required String winnerId, required String reason, required bool authorized, String? actorId}) async {
    if (!authorized) throw StateError('Only an authorized manager can correct a game result.');
    if (reason.trim().isEmpty) throw ArgumentError('A correction reason is required.');
    final db = await DBService.instance.database;
    late Map<String, Object?> game;
    late Map<String, Object?> event;
    await db.transaction((txn) async {
      final rows = await txn.query('snooker_games', where: 'id = ?', whereArgs: [gameId], limit: 1);
      if (rows.isEmpty || rows.first['status'] != 'completed') throw StateError('Only completed games can be corrected.');
      final previous = rows.first['winnerId']?.toString();
      final payments = await txn.query('snooker_payments', where: 'gameId = ?', whereArgs: [gameId], limit: 1);
      if (payments.isNotEmpty) throw StateError('Refund or reconcile existing payments before correcting this result.');
      if (winnerId != rows.first['playerAId'] && winnerId != rows.first['playerBId']) throw ArgumentError('Winner must be one of the two players.');
      if (previous == winnerId) throw StateError('The selected winner is already recorded.');
      game = {...rows.first, 'winnerId': winnerId, 'updatedAt': _now()};
      event = {
        'id': _uuid.v4(), 'gameId': gameId, 'eventType': 'result_corrected',
        'previousValue': previous, 'newValue': winnerId, 'reason': reason.trim(),
        'actorId': actorId, 'occurredAt': _now(), 'idempotencyKey': 'event:${_uuid.v4()}',
      };
      await txn.update('snooker_games', game, where: 'id = ?', whereArgs: [gameId]);
      await txn.insert('snooker_game_events', event);
    });
    await _queue('update', 'snooker_games', gameId, game);
    await _queue('create', 'snooker_game_events', event['id']! as String, event);
  }

  Future<double> _netPaid(Transaction txn, String gameId) async {
    final rows = await txn.rawQuery(
      "SELECT COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE -amount END),0) AS paid FROM snooker_payments WHERE gameId = ?",
      [gameId],
    );
    return (rows.first['paid'] as num?)?.toDouble() ?? 0;
  }

  Future<String> recordPayment({
    required String gameId,
    required double amount,
    required String method,
    required String payerId,
    String? reference,
    String? idempotencyKey,
    String? actorId,
    String? note,
  }) async {
    if (!amount.isFinite || amount <= 0) throw ArgumentError('Payment must be greater than zero.');
    if (!{'cash','bank','card','wallet','other'}.contains(method)) throw ArgumentError('Unsupported payment method.');
    final db = await DBService.instance.database;
    final id = _uuid.v4();
    final now = _now();
    final key = idempotencyKey?.trim().isNotEmpty == true
        ? idempotencyKey!.trim()
        : 'payment:$gameId:$payerId:${amount.toStringAsFixed(2)}:$method:${now.substring(0, 16)}';
    late Map<String, Object?> payment;
    await db.transaction((txn) async {
      final games = await txn.query('snooker_games', where: 'id = ?', whereArgs: [gameId], limit: 1);
      final fees = await txn.query('snooker_game_fees', where: 'gameId = ?', whereArgs: [gameId], limit: 1);
      if (games.isEmpty || games.first['status'] != 'completed' || fees.isEmpty) throw StateError('Complete the game before collecting its fee.');
      final loserId = games.first['winnerId'] == games.first['playerAId'] ? games.first['playerBId'] : games.first['playerAId'];
      if (payerId != loserId) throw ArgumentError('The losing player is responsible for the game fee.');
      final paid = await _netPaid(txn, gameId);
      final total = (fees.first['finalAmount'] as num).toDouble();
      if (paid + amount > total + 0.000001) throw StateError('Payment exceeds the outstanding game fee.');
      payment = {
        'id': id, 'gameId': gameId, 'payerId': payerId, 'amount': amount, 'method': method, 'type': 'payment',
        'reference': reference, 'idempotencyKey': key, 'receivedAt': now, 'receivedBy': actorId, 'note': note,
      };
      await txn.insert('snooker_payments', payment);
    });
    await _queue('create', 'snooker_payments', id, payment);
    return id;
  }

  Future<String> refundPayment({
    required String gameId,
    required double amount,
    required String method,
    required String reason,
    String? idempotencyKey,
    String? actorId,
  }) async {
    if (!amount.isFinite || amount <= 0 || reason.trim().isEmpty) throw ArgumentError('Refund amount and reason are required.');
    if (!{'cash','bank','card','wallet','other'}.contains(method)) throw ArgumentError('Unsupported refund method.');
    final db = await DBService.instance.database;
    final id = _uuid.v4();
    final now = _now();
    late Map<String, Object?> payment;
    await db.transaction((txn) async {
      final fees = await txn.query('snooker_game_fees', where: 'gameId = ?', whereArgs: [gameId], limit: 1);
      if (fees.isEmpty) throw StateError('Game fee not found.');
      final paid = await _netPaid(txn, gameId);
      if (amount > paid + 0.000001) throw StateError('Refund exceeds the net amount received.');
      payment = {
        'id': id, 'gameId': gameId, 'payerId': null, 'amount': amount, 'method': method, 'type': 'refund',
        'reference': null, 'idempotencyKey': idempotencyKey?.trim().isNotEmpty == true
            ? idempotencyKey!.trim()
            : 'refund:$gameId:${amount.toStringAsFixed(2)}:$method:${reason.trim().toLowerCase()}',
        'receivedAt': now, 'receivedBy': actorId, 'note': reason.trim(),
      };
      await txn.insert('snooker_payments', payment);
    });
    await _queue('create', 'snooker_payments', id, payment);
    return id;
  }

  Future<String> addExpense({required String category, required double amount, String paymentMethod = 'cash', String? note, String? actorId, String? idempotencyKey}) async {
    if (category.trim().isEmpty || !amount.isFinite || amount <= 0) throw ArgumentError('Expense category and positive amount are required.');
    if (!{'cash','bank','card','wallet','other'}.contains(paymentMethod)) throw ArgumentError('Unsupported payment method.');
    final db = await DBService.instance.database;
    final id = _uuid.v4();
    final row = {
      'id': id, 'category': category.trim(), 'amount': amount, 'paymentMethod': paymentMethod,
      'occurredAt': _now(), 'note': note, 'createdBy': actorId,
      'idempotencyKey': idempotencyKey?.trim().isNotEmpty == true ? idempotencyKey!.trim() : 'expense:$id',
    };
    await db.insert('snooker_expenses', row);
    await _queue('create', 'snooker_expenses', id, row);
    return id;
  }

  Future<String> openCashSession({required double openingCash, String? actorId, String? note}) async {
    if (!openingCash.isFinite || openingCash < 0) throw ArgumentError('Opening cash cannot be negative.');
    final db = await DBService.instance.database;
    final openSessions = await db.query(
      'snooker_cash_sessions',
      columns: ['id'],
      where: 'closedAt IS NULL',
      limit: 1,
    );
    if (openSessions.isNotEmpty) {
      throw StateError('A cash session is already open. Close it before starting another.');
    }
    final id = _uuid.v4();
    final row = {
      'id': id, 'openingCash': openingCash, 'expectedClosingCash': null,
      'actualClosingCash': null, 'difference': null, 'openedAt': _now(),
      'closedAt': null, 'openedBy': actorId, 'closedBy': null, 'note': note,
    };
    await db.insert('snooker_cash_sessions', row);
    await _queue('create', 'snooker_cash_sessions', id, row);
    return id;
  }

  Future<void> closeCashSession({required String sessionId, required double actualClosingCash, String? actorId}) async {
    if (!actualClosingCash.isFinite || actualClosingCash < 0) throw ArgumentError('Actual closing cash cannot be negative.');
    final db = await DBService.instance.database;
    late Map<String, Object?> updated;
    await db.transaction((txn) async {
      final rows = await txn.query('snooker_cash_sessions', where: 'id = ? AND closedAt IS NULL', whereArgs: [sessionId], limit: 1);
      if (rows.isEmpty) throw StateError('Open cash session not found.');
      final session = rows.first;
      final from = session['openedAt']! as String;
      final to = _now();
      final inflow = await txn.rawQuery("SELECT COALESCE(SUM(amount),0) AS total FROM snooker_payments WHERE method='cash' AND type='payment' AND receivedAt >= ? AND receivedAt <= ?", [from,to]);
      final refunds = await txn.rawQuery("SELECT COALESCE(SUM(amount),0) AS total FROM snooker_payments WHERE method='cash' AND type='refund' AND receivedAt >= ? AND receivedAt <= ?", [from,to]);
      final expenses = await txn.rawQuery("SELECT COALESCE(SUM(amount),0) AS total FROM snooker_expenses WHERE paymentMethod='cash' AND occurredAt >= ? AND occurredAt <= ?", [from,to]);
      final posCash = await txn.rawQuery("""
        SELECT COALESCE(SUM(pa.amount),0) AS total
        FROM payment_allocations pa JOIN bills b ON b.id = pa.billId
        WHERE pa.method = 'cash' AND b.date >= ? AND b.date <= ?
      """, [from, to]);
      final posCashRefunds = await txn.rawQuery("""
        SELECT COALESCE(SUM(refundAmount),0) AS total
        FROM bill_returns WHERE refundMethod = 'cash' AND date >= ? AND date <= ?
      """, [from, to]);
      // Club game payments and ordinary POS receipts share the till.
      // Include POS tender allocations and POS refunds exactly once; refreshment
      // sales are not added separately here because their cash tender is already
      // represented by payment_allocations.
      final expected = (session['openingCash'] as num).toDouble()
          + (inflow.first['total'] as num).toDouble()
          + (posCash.first['total'] as num).toDouble()
          - (refunds.first['total'] as num).toDouble()
          - (posCashRefunds.first['total'] as num).toDouble()
          - (expenses.first['total'] as num).toDouble();
      updated = {
        ...session, 'expectedClosingCash': expected, 'actualClosingCash': actualClosingCash,
        'difference': actualClosingCash - expected, 'closedAt': to, 'closedBy': actorId,
      };
      await txn.update('snooker_cash_sessions', updated, where: 'id = ?', whereArgs: [sessionId]);
    });
    await _queue('update', 'snooker_cash_sessions', sessionId, updated);
  }


  Future<List<Map<String, Object?>>> inventoryItems() async {
    return (await DBService.instance.database).query('snooker_inventory_items', orderBy: 'category ASC, name COLLATE NOCASE ASC');
  }

  Future<List<Map<String, Object?>>> equipmentAssets({String? assetType}) async {
    final db = await DBService.instance.database;
    if (assetType == null) {
      return db.rawQuery("""
        SELECT a.*, l.assetNumber AS lockerNumber, t.name AS tableName, p.name AS assignedPlayer
        FROM snooker_equipment_assets a
        LEFT JOIN snooker_equipment_assets l ON l.id = a.lockerAssetId
        LEFT JOIN snooker_tables t ON t.id = a.tableId
        LEFT JOIN snooker_players p ON p.id = a.assignedPlayerId
        ORDER BY a.assetType ASC, a.assetNumber COLLATE NOCASE ASC
      """);
    }
    return db.rawQuery("""
      SELECT a.*, l.assetNumber AS lockerNumber, t.name AS tableName, p.name AS assignedPlayer
      FROM snooker_equipment_assets a
      LEFT JOIN snooker_equipment_assets l ON l.id = a.lockerAssetId
      LEFT JOIN snooker_tables t ON t.id = a.tableId
      LEFT JOIN snooker_players p ON p.id = a.assignedPlayerId
      WHERE a.assetType = ?
      ORDER BY a.assetNumber COLLATE NOCASE ASC
    """, [assetType]);
  }

  Future<List<Map<String, Object?>>> equipmentMovements({int limit = 100}) async {
    return (await DBService.instance.database).rawQuery("""
      SELECT m.*, a.assetNumber, a.name AS assetName, i.name AS inventoryName
      FROM snooker_equipment_movements m
      LEFT JOIN snooker_equipment_assets a ON a.id = m.assetId
      LEFT JOIN snooker_inventory_items i ON i.id = m.inventoryItemId
      ORDER BY m.occurredAt DESC LIMIT ?
    """, [limit]);
  }

  Future<String> addEquipmentAsset({
    required String assetType,
    required String assetNumber,
    required String name,
    String? lockerAssetId,
    String? tableId,
    String? notes,
    String? actorId,
  }) async {
    if (!const ['cue', 'ball_set', 'locker'].contains(assetType)) throw ArgumentError('Invalid equipment type.');
    final number = assetNumber.trim();
    if (number.isEmpty || name.trim().isEmpty) throw ArgumentError('Asset number and name are required.');
    final db = await DBService.instance.database;
    final id = _uuid.v4();
    final now = _now();
    late Map<String, Object?> movement;
    final row = <String, Object?>{
      'id': id, 'assetType': assetType, 'assetNumber': number, 'name': name.trim(),
      'status': 'available', 'assignedToName': null, 'assignedPlayerId': null,
      'lockerAssetId': lockerAssetId, 'tableId': tableId, 'notes': notes?.trim(),
      'createdAt': now, 'updatedAt': now,
    };
    await db.transaction((txn) async {
      if (lockerAssetId != null) {
        final lockers = await txn.query('snooker_equipment_assets', where: "id = ? AND assetType = 'locker'", whereArgs: [lockerAssetId], limit: 1);
        if (lockers.isEmpty) throw StateError('Selected locker does not exist.');
      }
      if (tableId != null) {
        final tables = await txn.query('snooker_tables', where: 'id = ?', whereArgs: [tableId], limit: 1);
        if (tables.isEmpty) throw StateError('Selected table does not exist.');
      }
      await txn.insert('snooker_equipment_assets', row);
      movement = {
        'id': _uuid.v4(), 'assetId': id, 'inventoryItemId': null, 'movementType': 'opening_stock',
        'quantity': 1, 'personName': null, 'fromLocation': null, 'toLocation': 'club',
        'note': 'Asset registered', 'occurredAt': now, 'actorId': actorId,
      };
      await txn.insert('snooker_equipment_movements', movement);
    });
    await _queue('create', 'snooker_equipment_assets', id, row);
    await _queue('create', 'snooker_equipment_movements', movement['id']! as String, movement);
    return id;
  }

  Future<String> addInventoryItem({
    required String name,
    required String category,
    required String unit,
    required double openingQuantity,
    required double minimumQuantity,
    String? actorId,
  }) async {
    if (!const ['chalk', 'tip', 'glove', 'other'].contains(category)) throw ArgumentError('Invalid inventory category.');
    if (name.trim().isEmpty || unit.trim().isEmpty || !openingQuantity.isFinite || openingQuantity < 0 || !minimumQuantity.isFinite || minimumQuantity < 0) {
      throw ArgumentError('Enter a valid item name and non-negative quantities.');
    }
    final db = await DBService.instance.database;
    final id = _uuid.v4();
    final now = _now();
    late Map<String, Object?> movement;
    final row = <String, Object?>{
      'id': id, 'name': name.trim(), 'category': category, 'unit': unit.trim(),
      'quantity': openingQuantity, 'minimumQuantity': minimumQuantity, 'updatedAt': now,
    };
    await db.transaction((txn) async {
      await txn.insert('snooker_inventory_items', row);
      movement = {
        'id': _uuid.v4(), 'assetId': null, 'inventoryItemId': id,
        'movementType': 'opening_stock', 'quantity': openingQuantity, 'personName': null,
        'fromLocation': null, 'toLocation': 'club', 'note': 'Opening stock',
        'occurredAt': now, 'actorId': actorId,
      };
      await txn.insert('snooker_equipment_movements', movement);
    });
    await _queue('create', 'snooker_inventory_items', id, row);
    await _queue('create', 'snooker_equipment_movements', movement['id']! as String, movement);
    return id;
  }

  Future<void> adjustInventory({
    required String itemId,
    required double quantityChange,
    required String movementType,
    String? note,
    String? actorId,
  }) async {
    if (!quantityChange.isFinite || quantityChange == 0) throw ArgumentError('Quantity change cannot be zero.');
    if (!const ['purchase', 'consume', 'damage', 'adjustment'].contains(movementType)) throw ArgumentError('Invalid stock movement.');
    final db = await DBService.instance.database;
    late Map<String, Object?> updated;
    late Map<String, Object?> movement;
    await db.transaction((txn) async {
      final rows = await txn.query('snooker_inventory_items', where: 'id = ?', whereArgs: [itemId], limit: 1);
      if (rows.isEmpty) throw StateError('Inventory item not found.');
      final old = (rows.first['quantity'] as num).toDouble();
      final next = old + quantityChange;
      if (next < 0) throw StateError('Insufficient stock.');
      if (movementType == 'purchase' && quantityChange < 0) throw ArgumentError('A purchase must increase stock.');
      if (movementType == 'consume' && quantityChange > 0) throw ArgumentError('Consumption must reduce stock.');
      updated = {...rows.first, 'quantity': next, 'updatedAt': _now()};
      await txn.update('snooker_inventory_items', updated, where: 'id = ?', whereArgs: [itemId]);
      movement = {
        'id': _uuid.v4(), 'assetId': null, 'inventoryItemId': itemId,
        'movementType': movementType, 'quantity': quantityChange, 'personName': null,
        'fromLocation': quantityChange < 0 ? 'club' : null, 'toLocation': quantityChange > 0 ? 'club' : null,
        'note': note?.trim(), 'occurredAt': _now(), 'actorId': actorId,
      };
      await txn.insert('snooker_equipment_movements', movement);
    });
    await _queue('update', 'snooker_inventory_items', itemId, updated);
    await _queue('create', 'snooker_equipment_movements', movement['id']! as String, movement);
  }

  Future<void> assignEquipment({
    required String assetId,
    required String personName,
    String? playerId,
    String? lockerAssetId,
    String? tableId,
    String? actorId,
  }) async {
    final cleanName = personName.trim();
    if (cleanName.isEmpty) throw ArgumentError('Enter the person responsible for the equipment.');
    final db = await DBService.instance.database;
    late Map<String, Object?> updated;
    late Map<String, Object?> movement;
    Map<String, Object?>? lockerUpdated;
    Map<String, Object?>? lockerMovement;
    await db.transaction((txn) async {
      final rows = await txn.query('snooker_equipment_assets', where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (rows.isEmpty) throw StateError('Equipment asset not found.');
      if (rows.first['status'] == 'retired' || rows.first['status'] == 'missing' || rows.first['status'] == 'repair') {
        throw StateError('Missing, repair or retired equipment cannot be assigned.');
      }
      if (rows.first['status'] == 'in_use') throw StateError('Equipment is already assigned; return it before re-issuing.');
      if (playerId != null) {
        final players = await txn.query('snooker_players', where: 'id = ?', whereArgs: [playerId], limit: 1);
        if (players.isEmpty) throw StateError('Player not found.');
      }
      if (lockerAssetId != null) {
        final lockers = await txn.query('snooker_equipment_assets', where: "id = ? AND assetType = 'locker'", whereArgs: [lockerAssetId], limit: 1);
        if (lockers.isEmpty) throw StateError('Locker not found.');
        final locker = lockers.first;
        if (locker['status'] == 'missing' || locker['status'] == 'repair' || locker['status'] == 'retired') {
          throw StateError('Missing, repair or retired lockers cannot be assigned.');
        }
        final lockerHolder = locker['assignedToName']?.toString().trim().toLowerCase();
        if (locker['status'] == 'in_use' && lockerHolder != cleanName.toLowerCase()) {
          throw StateError('This locker is already assigned to another person.');
        }
        if (locker['status'] == 'available') {
          final lockerNow = _now();
          lockerUpdated = {...locker, 'status': 'in_use', 'assignedToName': cleanName, 'assignedPlayerId': playerId, 'updatedAt': lockerNow};
          await txn.update('snooker_equipment_assets', lockerUpdated!, where: 'id = ?', whereArgs: [lockerAssetId]);
          lockerMovement = {
            'id': _uuid.v4(), 'assetId': lockerAssetId, 'inventoryItemId': null, 'movementType': 'issue',
            'quantity': 1, 'personName': cleanName, 'fromLocation': 'club', 'toLocation': cleanName,
            'note': 'Locker assigned with equipment', 'occurredAt': lockerNow, 'actorId': actorId,
          };
          await txn.insert('snooker_equipment_movements', lockerMovement!);
        }
      }
      if (tableId != null) {
        final tables = await txn.query('snooker_tables', where: 'id = ?', whereArgs: [tableId], limit: 1);
        if (tables.isEmpty) throw StateError('Table not found.');
      }
      updated = {...rows.first, 'status': 'in_use', 'assignedToName': cleanName, 'assignedPlayerId': playerId, 'lockerAssetId': lockerAssetId, 'tableId': tableId, 'updatedAt': _now()};
      await txn.update('snooker_equipment_assets', updated, where: 'id = ?', whereArgs: [assetId]);
      movement = {
        'id': _uuid.v4(), 'assetId': assetId, 'inventoryItemId': null, 'movementType': 'issue',
        'quantity': 1, 'personName': cleanName, 'fromLocation': 'club', 'toLocation': tableId ?? lockerAssetId ?? cleanName,
        'note': null, 'occurredAt': _now(), 'actorId': actorId,
      };
      await txn.insert('snooker_equipment_movements', movement);
    });
    await _queue('update', 'snooker_equipment_assets', assetId, updated);
    await _queue('create', 'snooker_equipment_movements', movement['id']! as String, movement);
    if (lockerUpdated != null && lockerAssetId != null) {
      await _queue('update', 'snooker_equipment_assets', lockerAssetId, lockerUpdated!);
    }
    if (lockerMovement != null) {
      await _queue('create', 'snooker_equipment_movements', lockerMovement!['id']! as String, lockerMovement!);
    }
  }

  Future<void> returnEquipment({required String assetId, String? note, String? actorId}) async {
    final db = await DBService.instance.database;
    late Map<String, Object?> updated;
    late Map<String, Object?> movement;
    Map<String, Object?>? lockerUpdated;
    Map<String, Object?>? lockerMovement;
    await db.transaction((txn) async {
      final rows = await txn.query('snooker_equipment_assets', where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (rows.isEmpty) throw StateError('Equipment asset not found.');
      final original = rows.first;
      if (original['status'] != 'in_use') throw StateError('This equipment is not currently issued.');
      final now = _now();
      final lockerId = original['lockerAssetId']?.toString();
      updated = {...original, 'status': 'available', 'assignedToName': null, 'assignedPlayerId': null, 'lockerAssetId': null, 'tableId': null, 'updatedAt': now};
      await txn.update('snooker_equipment_assets', updated, where: 'id = ?', whereArgs: [assetId]);
      movement = {
        'id': _uuid.v4(), 'assetId': assetId, 'inventoryItemId': null, 'movementType': 'return',
        'quantity': 1, 'personName': original['assignedToName'], 'fromLocation': original['assignedToName'],
        'toLocation': 'club', 'note': note?.trim(), 'occurredAt': now, 'actorId': actorId,
      };
      await txn.insert('snooker_equipment_movements', movement);
      if (lockerId != null) {
        final otherAssignments = await txn.query(
          'snooker_equipment_assets',
          columns: ['id'],
          where: "lockerAssetId = ? AND status = 'in_use' AND id != ?",
          whereArgs: [lockerId, assetId],
          limit: 1,
        );
        if (otherAssignments.isEmpty) {
          final lockerRows = await txn.query('snooker_equipment_assets', where: "id = ? AND assetType = 'locker' AND status = 'in_use'", whereArgs: [lockerId], limit: 1);
          if (lockerRows.isNotEmpty) {
            lockerUpdated = {...lockerRows.first, 'status': 'available', 'assignedToName': null, 'assignedPlayerId': null, 'updatedAt': now};
            await txn.update('snooker_equipment_assets', lockerUpdated!, where: 'id = ?', whereArgs: [lockerId]);
            lockerMovement = {
              'id': _uuid.v4(), 'assetId': lockerId, 'inventoryItemId': null, 'movementType': 'return',
              'quantity': 1, 'personName': original['assignedToName'], 'fromLocation': original['assignedToName'],
              'toLocation': 'club', 'note': 'Locker released after all assigned equipment was returned',
              'occurredAt': now, 'actorId': actorId,
            };
            await txn.insert('snooker_equipment_movements', lockerMovement!);
          }
        }
      }
    });
    await _queue('update', 'snooker_equipment_assets', assetId, updated);
    await _queue('create', 'snooker_equipment_movements', movement['id']! as String, movement);
    if (lockerUpdated != null) {
      await _queue('update', 'snooker_equipment_assets', lockerUpdated!['id']! as String, lockerUpdated!);
    }
    if (lockerMovement != null) {
      await _queue('create', 'snooker_equipment_movements', lockerMovement!['id']! as String, lockerMovement!);
    }
  }

  Future<void> setEquipmentStatus({
    required String assetId,
    required String status,
    String? note,
    String? actorId,
  }) async {
    if (!const ['available', 'repair', 'missing', 'retired'].contains(status)) throw ArgumentError('Invalid equipment status.');
    final db = await DBService.instance.database;
    late Map<String, Object?> updated;
    late Map<String, Object?> movement;
    await db.transaction((txn) async {
      final rows = await txn.query('snooker_equipment_assets', where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (rows.isEmpty) throw StateError('Equipment asset not found.');
      if (rows.first['status'] == 'in_use' && status == 'available') throw StateError('Use Return to register an issued item coming back.');
      updated = {...rows.first, 'status': status, 'assignedToName': status == 'available' ? null : rows.first['assignedToName'], 'assignedPlayerId': status == 'available' ? null : rows.first['assignedPlayerId'], 'updatedAt': _now()};
      await txn.update('snooker_equipment_assets', updated, where: 'id = ?', whereArgs: [assetId]);
      movement = {
        'id': _uuid.v4(), 'assetId': assetId, 'inventoryItemId': null, 'movementType': status == 'repair' ? 'repair' : status == 'missing' ? 'missing' : status == 'retired' ? 'retire' : 'repair_return',
        'quantity': 1, 'personName': rows.first['assignedToName'], 'fromLocation': rows.first['status'],
        'toLocation': status, 'note': note?.trim(), 'occurredAt': _now(), 'actorId': actorId,
      };
      await txn.insert('snooker_equipment_movements', movement);
    });
    await _queue('update', 'snooker_equipment_assets', assetId, updated);
    await _queue('create', 'snooker_equipment_movements', movement['id']! as String, movement);
  }

  Future<List<Map<String, Object?>>> games({String? status}) async {
    final db = await DBService.instance.database;
    final where = status == null ? '' : 'WHERE g.status = ?';
    final args = status == null ? <Object?>[] : <Object?>[status];
    return db.rawQuery('''
      SELECT g.*, t.name AS tableName, f.feeAmount, f.discountAmount, f.finalAmount,
        COALESCE((SELECT SUM(CASE WHEN p.type='payment' THEN p.amount ELSE -p.amount END) FROM snooker_payments p WHERE p.gameId=g.id),0) AS netPaid
      FROM snooker_games g
      JOIN snooker_tables t ON t.id=g.tableId
      LEFT JOIN snooker_game_fees f ON f.gameId=g.id
      $where
      ORDER BY g.startedAt DESC
    ''', args);
  }

  Future<Map<String, Object?>> dailyReport({DateTime? from, DateTime? to}) async {
    final db = await DBService.instance.database;
    final start = DateTime(from?.year ?? DateTime.now().year, from?.month ?? DateTime.now().month, from?.day ?? DateTime.now().day).toIso8601String();
    final endDate = to ?? DateTime.now();
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999).toIso8601String();
    final gameFees = await db.rawQuery('''
      SELECT COALESCE(SUM(f.finalAmount),0) AS total, COUNT(g.id) AS games
      FROM snooker_games g JOIN snooker_game_fees f ON f.gameId=g.id
      WHERE g.status='completed' AND g.endedAt >= ? AND g.endedAt <= ?
    ''', [start, end]);
    final payments = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE -amount END),0) AS net,
        COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END),0) AS received,
        COALESCE(SUM(CASE WHEN type='refund' THEN amount ELSE 0 END),0) AS refunded
      FROM snooker_payments WHERE receivedAt >= ? AND receivedAt <= ?
    ''', [start, end]);
    final outstanding = await db.rawQuery('''
      SELECT COALESCE(SUM(f.finalAmount - COALESCE((
        SELECT SUM(CASE WHEN p.type='payment' THEN p.amount ELSE -p.amount END)
        FROM snooker_payments p WHERE p.gameId=g.id
      ),0)),0) AS total
      FROM snooker_games g JOIN snooker_game_fees f ON f.gameId=g.id
      WHERE g.status='completed' AND g.endedAt >= ? AND g.endedAt <= ?
    ''', [start, end]);
    final sales = await db.rawQuery('''
      SELECT COALESCE(SUM(salePrice * quantity),0) AS revenue,
        COALESCE(SUM(costPrice * quantity),0) AS cost
      FROM daily_sales WHERE source IN ('pos','return') AND date >= ? AND date <= ?
    ''', [start, end]);
    final expenses = await db.rawQuery('SELECT COALESCE(SUM(amount),0) AS total FROM snooker_expenses WHERE occurredAt >= ? AND occurredAt <= ?', [start, end]);
    final wins = await db.rawQuery('''
      SELECT p.name, COUNT(g.id) AS wins FROM snooker_games g
      JOIN snooker_players p ON p.id=g.winnerId
      WHERE g.status='completed' AND g.endedAt >= ? AND g.endedAt <= ?
      GROUP BY p.id, p.name ORDER BY wins DESC, p.name ASC
    ''', [start, end]);
    final feeTotal = (gameFees.first['total'] as num).toDouble();
    final refreshmentRevenue = (sales.first['revenue'] as num).toDouble();
    final refreshmentCost = (sales.first['cost'] as num).toDouble();
    final expenseTotal = (expenses.first['total'] as num).toDouble();
    final isFullMonth = from != null && to != null && from.year == to.year && from.month == to.month && from.day == 1 && to.day == DateTime(to.year, to.month + 1, 0).day;
    return {
      'from': start, 'to': end,
      'periodLabel': isFullMonth ? 'Monthly' : (from == null && to == null ? 'Daily' : 'Selected period'),
      'completedGames': (gameFees.first['games'] as num).toInt(),
      'gameFeesEarned': feeTotal,
      'paymentsReceived': (payments.first['received'] as num).toDouble(),
      'refunds': (payments.first['refunded'] as num).toDouble(),
      'netGamePayments': (payments.first['net'] as num).toDouble(),
      'outstandingGameFees': (outstanding.first['total'] as num).toDouble(),
      'refreshmentSales': refreshmentRevenue,
      'refreshmentCost': refreshmentCost,
      'snookerExpenses': expenseTotal,
      'operatingResultBeforeOtherCosts': feeTotal - (payments.first['refunded'] as num).toDouble() + refreshmentRevenue - refreshmentCost - expenseTotal,
      'playerWins': wins,
    };
  }

  Future<List<Map<String, Object?>>> recentPayments() async {
    return (await DBService.instance.database).rawQuery('''
      SELECT p.*, pl.name AS payerName
      FROM snooker_payments p
      LEFT JOIN snooker_players pl ON pl.id = p.payerId
      ORDER BY p.receivedAt DESC LIMIT 100
    ''');
  }

  Future<List<Map<String, Object?>>> expenses() async {
    return (await DBService.instance.database).query('snooker_expenses', orderBy: 'occurredAt DESC', limit: 100);
  }

  Future<List<Map<String, Object?>>> cashSessions() async {
    return (await DBService.instance.database).query('snooker_cash_sessions', orderBy: 'openedAt DESC', limit: 30);
  }

  Future<List<Map<String, Object?>>> gameEvents(String gameId) async {
    return (await DBService.instance.database).query('snooker_game_events', where: 'gameId = ?', whereArgs: [gameId], orderBy: 'occurredAt ASC');
  }
}
