import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/services/db_service.dart';
import 'package:shopkeeper_pro/services/snooker_club_service.dart';

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
      service.recordPayment(gameId: gameId, amount: 1, method: 'cash', payerId: game['playerAId']! as String),
      throwsStateError,
    );
    await service.refundPayment(gameId: gameId, amount: 50, method: 'cash', reason: 'Approved correction');
    await expectLater(
      service.refundPayment(gameId: gameId, amount: 251, method: 'cash', reason: 'Too much'),
      throwsStateError,
    );
    final report = await service.dailyReport();
    expect(report['completedGames'], 1);
    expect(report['gameFeesEarned'], 300);
    expect(report['paymentsReceived'], 300);
    expect(report['refunds'], 50);
    expect(report['outstandingGameFees'], 50);
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
    await service.recordPayment(gameId: gameId, amount: 200, method: 'cash', payerId: game['playerBId']! as String);
    await service.addExpense(category: 'Cleaning', amount: 50, paymentMethod: 'cash');
    await service.closeCashSession(sessionId: sessionId, actualClosingCash: 1150);
    final session = (await service.cashSessions()).first;
    expect(session['expectedClosingCash'], 1150);
    expect(session['actualClosingCash'], 1150);
    expect(session['difference'], 0);
    await expectLater(service.openCashSession(openingCash: 100), throwsA(anything));
  });

  test('game fee default is persisted across service reloads', () async {
    await service.setDefaultGameFee(450);
    expect(await service.defaultGameFee(), 450);
    final db = await DBService.instance.database;
    expect((await db.query('snooker_settings')).single['id'], 'defaultGameFee');
  });
}
