import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Represents the current connectivity state.
enum ConnectivityState {
  /// Connected to WiFi.
  wifi,

  /// Connected to mobile data.
  mobile,

  /// Connected to ethernet.
  ethernet,

  /// No internet connection.
  offline,
}

/// Extension methods for ConnectivityState.
extension ConnectivityStateExtension on ConnectivityState {
  /// Whether the device has any internet connection.
  bool get isOnline => this != ConnectivityState.offline;

  /// Whether the device is on WiFi (preferred for sync).
  bool get isWifi => this == ConnectivityState.wifi;

  /// Whether the device is on a metered connection (mobile data).
  bool get isMetered => this == ConnectivityState.mobile;
}

/// Service for monitoring network connectivity.
class ConnectivityService {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final _stateController = StreamController<ConnectivityState>.broadcast();

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        final state = _mapResultsToState(results);
        _stateController.add(state);
      },
      onError: (_) {
        // Platform channel type-cast failures — treat as online.
        _stateController.add(ConnectivityState.wifi);
      },
    );
  }

  /// Stream of connectivity state changes.
  Stream<ConnectivityState> get onConnectivityChanged => _stateController.stream;

  /// Get the current connectivity state.
  Future<ConnectivityState> get currentState async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _mapResultsToState(results);
    } catch (e) {
      // connectivity_plus platform channel can throw on some Android devices
      // (returns String instead of List); assume online so the app doesn't block.
      return ConnectivityState.wifi;
    }
  }

  /// Check if currently online.
  Future<bool> get isOnline async {
    final state = await currentState;
    return state.isOnline;
  }

  /// Check if currently on WiFi.
  Future<bool> get isWifi async {
    final state = await currentState;
    return state.isWifi;
  }

  /// Map a list of connectivity results to our state enum.
  /// Picks the "best" connection from the list.
  ConnectivityState _mapResultsToState(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return ConnectivityState.wifi;
    }
    if (results.contains(ConnectivityResult.ethernet)) {
      return ConnectivityState.ethernet;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return ConnectivityState.mobile;
    }
    if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return ConnectivityState.offline;
    }
    // VPN, bluetooth, or other connection types - treat as online.
    return ConnectivityState.wifi;
  }

  /// Dispose of the service and cancel subscriptions.
  void dispose() {
    _subscription?.cancel();
    _stateController.close();
  }
}
