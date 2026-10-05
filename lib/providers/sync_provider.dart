import 'package:flutter/foundation.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../services/connectivity_service.dart';

/// Provider to expose sync status to UI
class SyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  bool _isOnline = false;
  int _pendingOperations = 0;
  String? _lastSyncTime;

  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline;
  int get pendingOperations => _pendingOperations;
  String? get lastSyncTime => _lastSyncTime;

  /// Initialize sync monitoring
  Future<void> init(String userId) async {
    await SyncService.instance.init(userId);
    await ConnectivityService.instance.init(userId);
    await SyncQueueService.instance.init(userId);

    // Update UI state
    _updateStatus();
    notifyListeners();
  }

  /// Update sync status from services
  void _updateStatus() {
    _isSyncing = SyncService.instance.isSyncing;
    _isOnline = SyncService.instance.isOnline;
    _pendingOperations = SyncQueueService.instance.pendingCount;
    notifyListeners();
  }

  @override
  void dispose() {
    ConnectivityService.instance.dispose();
    SyncQueueService.instance.dispose();
    super.dispose();
  }

  /// Manual sync trigger
  Future<void> syncNow(String userId) async {
    _isSyncing = true;
    notifyListeners();

    try {
      // Sync pending offline operations
      if (SyncQueueService.instance.hasPending) {
        await SyncQueueService.instance.syncPendingOperations(userId);
      }

      // Sync from cloud
      await SyncService.instance.syncNow(userId);

      _lastSyncTime = DateTime.now().toString();
    } finally {
      _isSyncing = false;
      _updateStatus();
      notifyListeners();
    }
  }
}
