import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _keyHost = 'server_host';
  static const _keyPort = 'server_port';
  static const defaultHost = '192.168.1.100';
  static const defaultPort = 8080;

  String _host = defaultHost;
  int _port = defaultPort;
  bool _loaded = false;

  String get host => _host;
  int get port => _port;
  bool get isLoaded => _loaded;
  String get baseUrl => 'http://$_host:$_port';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_keyHost) ?? defaultHost;
    _port = prefs.getInt(_keyPort) ?? defaultPort;
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, host.trim());
    await prefs.setInt(_keyPort, port);
    _host = host.trim();
    _port = port;
    notifyListeners();
  }
}
