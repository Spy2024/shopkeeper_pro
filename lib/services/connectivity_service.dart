import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
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
    _isOnline = !(await _connectivity.checkConnectivity()).contains(ConnectivityResult.none);

    await _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = !result.contains(ConnectivityResult.none);
      if (!wasOnline && _isOnline && _userId != null) {
        unawaited(SyncService.instance.syncNow(_userId!));
      }
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _userId = null;
  }
}
