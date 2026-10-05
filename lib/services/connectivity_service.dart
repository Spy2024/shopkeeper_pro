import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'sync_queue_service.dart';
import 'sync_service.dart';

class ConnectivityService {
  ConnectivityService._internal();
  static final ConnectivityService instance = ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnline = false;
  String? _userId;

  bool get isOnline => _isOnline;

  Future<void> init(String userId) async {
    _userId = userId;
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasNetwork(result);

    await _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = _hasNetwork(result);
      if (!wasOnline && _isOnline) {
        unawaited(_triggerSync());
      }
    });
  }

  bool _hasNetwork(List<ConnectivityResult> result) =>
      result.any((r) => r != ConnectivityResult.none);

  Future<void> _triggerSync() async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return;
    try {
      await SyncQueueService.instance.syncPendingOperations(uid);
      await SyncService.instance.syncNow(uid);
    } catch (e) {
      debugPrint('[Connectivity] sync error: $e');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _userId = null;
  }
}
