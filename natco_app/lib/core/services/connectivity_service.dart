/// Connectivity, in two parts.
///
/// `connectivity_plus` answers "is there a network interface?" and
/// `internet_connection_checker_plus` answers "does it go anywhere?". Both are
/// needed: a school Wi-Fi that hands out a DHCP lease with no upstream is the
/// normal case, and treating an interface as reachability produces a sync
/// engine that hammers a dead link and reports success it never had
/// (docs/06-offline-sync-strategy.md, section 7).
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// What the app knows about its connection.
enum ConnectionStatus {
  /// No interface at all.
  offline,

  /// An interface exists but nothing reachable was found behind it.
  interfaceOnly,

  /// Reachable over a metered mobile connection.
  onlineMetered,

  /// Reachable over an unmetered connection (Wi-Fi, ethernet).
  onlineUnmetered;

  /// Whether requests can be attempted.
  bool get isReachable =>
      this == ConnectionStatus.onlineMetered ||
      this == ConnectionStatus.onlineUnmetered;

  /// Whether large uploads (OMR images) should proceed by default.
  ///
  /// Teachers on prepaid data should not lose a day's balance to a batch of
  /// photographs; the default is Wi-Fi-only, overridable in settings.
  bool get isSuitableForLargeUploads =>
      this == ConnectionStatus.onlineUnmetered;
}

abstract interface class ConnectivityService {
  /// Current status.
  Future<ConnectionStatus> current();

  /// Emits on every change. Never emits duplicate consecutive values.
  Stream<ConnectionStatus> changes();

  /// Releases platform subscriptions.
  Future<void> dispose();
}

/// Production implementation.
final class PlatformConnectivityService implements ConnectivityService {
  PlatformConnectivityService({
    Connectivity? connectivity,
    InternetConnection? reachability,
  }) : _connectivity = connectivity ?? Connectivity(),
       _reachability = reachability ?? InternetConnection.createInstance();

  final Connectivity _connectivity;
  final InternetConnection _reachability;

  StreamController<ConnectionStatus>? _controller;
  StreamSubscription<List<ConnectivityResult>>? _interfaceSubscription;
  StreamSubscription<InternetStatus>? _reachabilitySubscription;
  ConnectionStatus? _last;

  @override
  Future<ConnectionStatus> current() async {
    final List<ConnectivityResult> interfaces = await _connectivity
        .checkConnectivity();
    return _resolve(interfaces, await _reachability.hasInternetAccess);
  }

  @override
  Stream<ConnectionStatus> changes() {
    // The controller outlives this method by design: it is created lazily on
    // first subscription and closed in [dispose]. `close_sinks` cannot see
    // that across methods.
    // ignore: close_sinks
    final StreamController<ConnectionStatus> controller = _controller ??=
        StreamController<ConnectionStatus>.broadcast(
          onListen: _attach,
          onCancel: _detach,
        );
    return controller.stream;
  }

  void _attach() {
    _interfaceSubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> _) => unawaited(_emitCurrent()),
    );
    _reachabilitySubscription = _reachability.onStatusChange.listen(
      (InternetStatus _) => unawaited(_emitCurrent()),
    );
    unawaited(_emitCurrent());
  }

  void _detach() {
    unawaited(_interfaceSubscription?.cancel());
    unawaited(_reachabilitySubscription?.cancel());
    _interfaceSubscription = null;
    _reachabilitySubscription = null;
  }

  Future<void> _emitCurrent() async {
    final ConnectionStatus status = await current();
    if (status == _last) {
      return;
    }
    _last = status;
    _controller?.add(status);
  }

  static ConnectionStatus _resolve(
    List<ConnectivityResult> interfaces,
    bool hasInternet,
  ) {
    final bool hasInterface = interfaces.any(
      (ConnectivityResult r) => r != ConnectivityResult.none,
    );
    if (!hasInterface) {
      return ConnectionStatus.offline;
    }
    if (!hasInternet) {
      return ConnectionStatus.interfaceOnly;
    }
    final bool metered =
        interfaces.contains(ConnectivityResult.mobile) &&
        !interfaces.contains(ConnectivityResult.wifi) &&
        !interfaces.contains(ConnectivityResult.ethernet);
    return metered
        ? ConnectionStatus.onlineMetered
        : ConnectionStatus.onlineUnmetered;
  }

  @override
  Future<void> dispose() async {
    _detach();
    await _controller?.close();
    _controller = null;
  }
}

/// Reports a fixed status. Used in tests and demo mode, where the status is
/// part of the scenario being exercised.
final class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService([this._status = ConnectionStatus.onlineUnmetered]);

  ConnectionStatus _status;
  final StreamController<ConnectionStatus> _controller =
      StreamController<ConnectionStatus>.broadcast();

  /// Pushes a new status to listeners.
  void emit(ConnectionStatus status) {
    if (status == _status) {
      return;
    }
    _status = status;
    _controller.add(status);
  }

  @override
  Future<ConnectionStatus> current() async => _status;

  @override
  Stream<ConnectionStatus> changes() => _controller.stream;

  @override
  Future<void> dispose() async => _controller.close();
}
