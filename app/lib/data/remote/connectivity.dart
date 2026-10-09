import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device has a network connection, then every change. Having
/// one does not prove the server is reachable: failed fetches tell that.
Stream<bool> deviceOnline() async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
}
