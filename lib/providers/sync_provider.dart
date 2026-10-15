import 'package:flutter/foundation.dart';
import '../services/sync_service.dart';
import '../services/sync_queue_service.dart';
import '../services/connectivity_service.dart';

class SyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  bool _isOnline = false;
  int _pendingOperations = 0;
  String? _lastSyncTime;

  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline;
  int get pendingOperations => _pendingOperations;
  String? get lastSyncTime => _lastSyncTime;

  Future<void> init(String userId) async {
    await SyncQueueService.instance.init(userId);
    await SyncService.instance.init(userId);
    await ConnectivityService.instance.init(userId);
    _updateStatus();
  }

  void _updateStatus() {
    _isSyncing = SyncService.instance.isSyncing;
    _isOnline = SyncService.instance.isOnline;
    _pendingOperations = SyncQueueService.instance.pendingCount;
    notifyListeners();
  }

  Future<void> syncNow(String userId) async {
    _isSyncing = true;
    notifyListeners();
    try {
      await SyncService.instance.syncNow(userId);
      _lastSyncTime = DateTime.now().toIso8601String();
    } finally {
      _updateStatus();
    }
  }
}
