import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/services/db_service.dart';
import 'package:shopkeeper_pro/services/snooker_club_service.dart';
import 'package:shopkeeper_pro/services/snooker_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = SnookerClubService.instance;
  late String userId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    userId = 'snooker-${DateTime.now().microsecondsSinceEpoch}';
    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(userId);
  });

  tearDown(() async {
    if (DBService.instance.activeUserId == userId) {
      await DBService.instance.deleteActiveUserDatabase(userId);
    }
  });

  test('creates nine tables by default and supports adding more', () async {
    final tables = await service.tables();
    expect(tables, hasLength(9));
    expect(tables.map((row) => row['tableNumber']).toList(), List<int>.generate(9, (i) => i + 1));
    await service.addTable();
    expect(await service.tables(), hasLength(10));
  });

  test('players that differ only by repeated whitespace are treated as the same player', () async {
    final table = (await service.tables()).first;
    await expectLater(
      service.startGame(
        tableId: table['id']! as String,
        playerA: 'Ali   Khan',
        playerB: ' ali Khan ',
        feeAmount: 300,
      ),
      throwsArgumentError,
    );
    expect(await service.games(), isEmpty);
  });

  test('one table cannot have duplicate active games and completion records winner', () async {
    final table = (await service.tables()).first;
    final gameId = await service.startGame(
      tableId: table['id']! as String,
      playerA: 'Ali',
      playerB: 'Ahmed',
      feeAmount: 300,
    );
    await expectLater(
      service.startGame(tableId: table['id']! as String, playerA: 'Usman', playerB: 'Bilal', feeAmount: 300),
      throwsStateError,
    );
    final db = await DBService.instance.database;
    final game = (await db.query('snooker_games', where: 'id = ?', whereArgs: [gameId])).single;
    await expectLater(
      service.completeGame(gameId: gameId, winnerId: 'not-a-player'),
      throwsArgumentError,
    );
    await service.completeGame(gameId: gameId, winnerId: game['playerAId']! as String);
    expect((await service.tables()).first['status'], 'available');
    expect((await service.games()).first['status'], 'completed');
    expect((await service.gameEvents(gameId)).map((e) => e['eventType']), containsAll(['started', 'completed']));
  });

  test('payment, partial balance, duplicate reference, refund and report reconcile', () async {
    final table = (await service.tables()).first;
    final gameId = await service.startGame(
      tableId: table['id']! as String,
      playerA: 'Player One',
      playerB: 'Player Two',
      feeAmount: 300,
    );
    final db = await DBService.instance.database;
    final game = (await db.query('snooker_games', where: 'id = ?', whereArgs: [gameId])).single;
    await service.completeGame(gameId: gameId, winnerId: game['playerBId']! as String);
    await service.recordPayment(gameId: gameId, amount: 100, method: 'cash', payerId: game['playerAId']! as String, reference: 'receipt-001');
    await expectLater(
      service.recordPayment(gameId: gameId, amount: 100, method: 'cash', payerId: game['playerAId']! as String, reference: 'receipt-001'),
      throwsA(anything),
    );
    await service.recordPayment(gameId: gameId, amount: 200, method: 'bank', payerId: game['playerAId']! as String);
    await expectLater(
      service.recordPayment(gameId: gameId, amount: 200, method: 'bank', payerId: game['playerAId']! as String),
      throwsA(anything),
    );
    await expectLater(
      service.recordPayment(gameId: gameId, amount: 1, method: 'cash', payerId: game['playerAId']! as String),
      throwsStateError,
    );
    await service.refundPayment(gameId: gameId, amount: 50, method: 'cash', reason: 'Approved correction');
    await expectLater(
      service.refundPayment(gameId: gameId, amount: 50, method: 'cash', reason: 'Approved correction'),
      throwsA(anything),
    );
    await expectLater(
      service.refundPayment(gameId: gameId, amount: 251, method: 'cash', reason: 'Too much'),
      throwsStateError,
    );
    final saleDate = DateTime.now().toIso8601String();
    await db.insert('daily_sales', {
      'id': 'snooker-refreshment-sale', 'date': saleDate,
      'productName': 'Cold drink', 'costPrice': 20.0, 'salePrice': 50.0,
      'quantity': 2, 'source': 'pos',
    });
    await db.insert('daily_sales', {
      'id': 'snooker-refreshment-return', 'date': saleDate,
      'productName': 'Cold drink', 'costPrice': -20.0, 'salePrice': -50.0,
      'quantity': 1, 'source': 'return',
    });
    final report = await service.dailyReport();
    expect(report['completedGames'], 1);
    expect(report['gameFeesEarned'], 300);
    expect(report['paymentsReceived'], 300);
    expect(report['refunds'], 50);
    expect(report['outstandingGameFees'], 50);
    expect(report['refreshmentSales'], 50);
    expect(report['refreshmentCost'], 20);
    expect(report['operatingResultBeforeOtherCosts'], 280);
  });

  test('cancellation releases table, logs reason, and result correction requires authorization', () async {
    final table = (await service.tables()).first;
    final gameId = await service.startGame(
      tableId: table['id']! as String,
      playerA: 'Cancel A',
      playerB: 'Cancel B',
      feeAmount: 250,
    );
    await service.cancelGame(gameId: gameId, reason: 'Table maintenance');
    expect((await service.tables()).first['status'], 'available');
    expect((await service.gameEvents(gameId)).last['reason'], 'Table maintenance');
    await expectLater(
      service.correctResult(gameId: gameId, winnerId: 'none', reason: 'No permission', authorized: false),
      throwsStateError,
    );
  });

  test('cash session reconciles game cash, refreshment POS cash and expenses', () async {
    final table = (await service.tables()).first;
    final gameId = await service.startGame(
      tableId: table['id']! as String,
      playerA: 'Cash A',
      playerB: 'Cash B',
      feeAmount: 200,
    );
    final db = await DBService.instance.database;
    final game = (await db.query('snooker_games', where: 'id = ?', whereArgs: [gameId])).single;
    await service.completeGame(gameId: gameId, winnerId: game['playerAId']! as String);
    final sessionId = await service.openCashSession(openingCash: 1000);
    await expectLater(service.openCashSession(openingCash: 100), throwsStateError);
    await service.recordPayment(gameId: gameId, amount: 200, method: 'cash', payerId: game['playerBId']! as String);
    await service.addExpense(category: 'Cleaning', amount: 50, paymentMethod: 'cash');
    final now = DateTime.now().toIso8601String();
    await db.insert('bills', {'id': 'snooker-pos-cash-bill', 'date': now});
    await db.insert('payment_allocations', {
      'id': 'snooker-pos-cash-payment', 'billId': 'snooker-pos-cash-bill',
      'method': 'cash', 'amount': 100, 'createdAt': now,
    });
    await db.insert('bill_returns', {
      'id': 'snooker-pos-cash-refund', 'billId': 'snooker-pos-cash-bill',
      'productId': 'test-product', 'productName': 'Test drink', 'quantity': 1,
      'refundAmount': 20, 'refundMethod': 'cash', 'date': now, 'reason': 'Test refund',
    });
    await service.closeCashSession(sessionId: sessionId, actualClosingCash: 1230);
    final session = (await service.cashSessions()).first;
    expect(session['expectedClosingCash'], 1230);
    expect(session['actualClosingCash'], 1230);
    expect(session['difference'], 0);
    final nextSessionId = await service.openCashSession(openingCash: 100);
    expect(nextSessionId, isNotEmpty);
  });

  test('equipment register tracks cues, ball sets, lockers, assignment and returns', () async {
    final lockerId = await service.addEquipmentAsset(assetType: 'locker', assetNumber: 'L-01', name: 'Locker 1');
    final cueId = await service.addEquipmentAsset(assetType: 'cue', assetNumber: 'C-01', name: 'Club cue 1');
    await service.assignEquipment(assetId: cueId, personName: 'Ali', lockerAssetId: lockerId);
    var assets = await service.equipmentAssets();
    final cue = assets.singleWhere((row) => row['id'] == cueId);
    expect(cue['status'], 'in_use');
    expect(cue['assignedToName'], 'Ali');
    expect(cue['lockerAssetId'], lockerId);
    expect(assets.singleWhere((row) => row['id'] == lockerId)['status'], 'in_use');
    expect(assets.singleWhere((row) => row['id'] == lockerId)['assignedToName'], 'Ali');
    final secondCueId = await service.addEquipmentAsset(assetType: 'cue', assetNumber: 'C-02', name: 'Club cue 2');
    await expectLater(
      service.assignEquipment(assetId: secondCueId, personName: 'Bilal', lockerAssetId: lockerId),
      throwsStateError,
    );
    expect((await service.equipmentAssets()).singleWhere((row) => row['id'] == secondCueId)['status'], 'available');
    await service.returnEquipment(assetId: cueId, note: 'Returned in good condition');
    assets = await service.equipmentAssets();
    expect(assets.singleWhere((row) => row['id'] == cueId)['status'], 'available');
    expect(assets.singleWhere((row) => row['id'] == lockerId)['status'], 'available');
    expect(assets.singleWhere((row) => row['id'] == lockerId)['assignedToName'], isNull);
    final ballId = await service.addEquipmentAsset(assetType: 'ball_set', assetNumber: 'B-01', name: 'Tournament balls');
    expect((await service.equipmentAssets(assetType: 'ball_set')).single['id'], ballId);
    expect((await service.equipmentMovements()).map((row) => row['movementType']), containsAll(['opening_stock', 'issue', 'return']));
  });

  test('chalk stock purchase, use and low stock quantity persist', () async {
    final itemId = await service.addInventoryItem(name: 'Blue chalk', category: 'chalk', unit: 'piece', openingQuantity: 20, minimumQuantity: 5);
    await service.adjustInventory(itemId: itemId, quantityChange: 10, movementType: 'purchase');
    await service.adjustInventory(itemId: itemId, quantityChange: -8, movementType: 'consume', note: 'Daily use');
    var items = await service.inventoryItems();
    expect(items.single['quantity'], 22);
    await expectLater(
      service.adjustInventory(itemId: itemId, quantityChange: -23, movementType: 'consume'),
      throwsStateError,
    );
    items = await service.inventoryItems();
    expect(items.single['quantity'], 22);
  });

  test('daily and monthly report PDF generation produces a PDF document', () async {
    final report = {
      'from': '2026-10-01T00:00:00.000',
      'to': '2026-10-31T23:59:59.999',
      'periodLabel': 'Monthly',
      'completedGames': 12,
      'gameFeesEarned': 3600.0,
      'paymentsReceived': 3200.0,
      'refunds': 100.0,
      'outstandingGameFees': 500.0,
      'refreshmentSales': 2400.0,
      'refreshmentCost': 1200.0,
      'snookerExpenses': 300.0,
      'operatingResultBeforeOtherCosts': 4500.0,
      'playerWins': [{'name': 'Ali', 'wins': 5}, {'name': 'Usman', 'wins': 3}],
    };
    final bytes = await SnookerReportService.buildDailyPdf(report);
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('snooker equipment remains isolated between two local account databases', () async {
    final cueId = await service.addEquipmentAsset(assetType: 'cue', assetNumber: 'ACCOUNT-A-CUE', name: 'Private cue');
    final otherUserId = '$userId-other';
    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(otherUserId);
    expect(await service.equipmentAssets(), isEmpty);
    await DBService.instance.deleteActiveUserDatabase(otherUserId);
    await DBService.instance.configureForUser(userId);
    expect((await service.equipmentAssets()).any((row) => row['id'] == cueId), isTrue);
  });

  test('games, payments, cues and stock survive a local database close and reopen', () async {
    final table = (await service.tables()).first;
    final gameId = await service.startGame(
      tableId: table['id']! as String,
      playerA: 'Restart Winner',
      playerB: 'Restart Loser',
      feeAmount: 150,
    );
    final db = await DBService.instance.database;
    final game = (await db.query('snooker_games', where: 'id = ?', whereArgs: [gameId])).single;
    await service.completeGame(gameId: gameId, winnerId: game['playerAId']! as String);
    await service.recordPayment(gameId: gameId, amount: 150, method: 'cash', payerId: game['playerBId']! as String, reference: 'restart-payment');
    final cueId = await service.addEquipmentAsset(assetType: 'cue', assetNumber: 'RESTART-CUE', name: 'Persistent cue');
    final stockId = await service.addInventoryItem(name: 'Persistent chalk', category: 'chalk', unit: 'piece', openingQuantity: 12, minimumQuantity: 2);

    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(userId);

    expect((await service.games()).any((row) => row['id'] == gameId), isTrue);
    expect((await service.recentPayments()).any((row) => row['reference'] == 'restart-payment'), isTrue);
    expect((await service.equipmentAssets()).any((row) => row['id'] == cueId), isTrue);
    expect((await service.inventoryItems()).singleWhere((row) => row['id'] == stockId)['quantity'], 12);
  });

  test('monthly report uses the full current month and labels its period', () async {
    final now = DateTime.now();
    final report = await service.dailyReport(
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month + 1, 0),
    );
    expect(report['periodLabel'], 'Monthly');
    expect((report['from'] as String).substring(0, 7), now.toIso8601String().substring(0, 7));
  });

  test('game fee default is persisted across service reloads', () async {
    await service.setDefaultGameFee(450);
    expect(await service.defaultGameFee(), 450);
    final db = await DBService.instance.database;
    expect((await db.query('snooker_settings')).single['id'], 'defaultGameFee');
  });
}
