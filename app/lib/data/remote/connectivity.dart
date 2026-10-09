import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device has a network connection, then every change. Having
/// one does not prove the server is reachable: failed fetches tell that.
Stream<bool> deviceOnline() async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
  try {
    yield online(await connectivity.checkConnectivity());
    yield* connectivity.onConnectivityChanged.map(online);
  } on Exception {
    // No plugin (tests, unsupported platform): the connection is unknown, so
    // nothing is reported; failed fetches still show as stale.
  }
}
