import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'sync_queue_service.dart';
import 'sync_service.dart';

/// Monitors network connectivity and triggers sync when online
class ConnectivityService {
  ConnectivityService._internal();
  static final ConnectivityService instance = ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _subscription;
  bool _isOnline = false;
  String? _userId;

  bool get isOnline => _isOnline;

  /// Initialize connectivity monitoring
  Future<void> init(String userId) async {
    _userId = userId;

    // Check initial state
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;

    debugPrint('[Connectivity] Initial state: ${_isOnline ? 'ONLINE' : 'OFFLINE'}');

    // Listen to changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;

      debugPrint(
          '[Connectivity] Status changed: ${_isOnline ? 'ONLINE' : 'OFFLINE'}');

      // Trigger sync when coming online
      if (!wasOnline && _isOnline && _userId != null) {
        debugPrint('[Connectivity] Triggering sync after coming online...');
        _triggerSync();
      }
    });
  }

  /// Trigger sync when connection restored
  Future<void> _triggerSync() async {
    if (_userId == null) return;

    try {
      // First, sync pending offline changes
      if (SyncQueueService.instance.hasPending) {
        debugPrint('[Connectivity] Syncing ${SyncQueueService.instance.pendingCount} pending operations...');
        await SyncQueueService.instance.syncPendingOperations(_userId!);
      }

      // Then, sync from cloud
      debugPrint('[Connectivity] Pulling latest data from cloud...');
      await SyncService.instance.syncFromCloud(_userId!);

      debugPrint('[Connectivity] Sync completed successfully');
    } catch (e) {
      debugPrint('[Connectivity] Sync error: $e');
    }
  }

  /// Dispose listener
  void dispose() {
    _subscription.cancel();
  }
}
