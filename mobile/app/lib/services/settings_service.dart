import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum InputMode { voice, text }
enum OutputMode { voice, text }

class SettingsService extends ChangeNotifier {
  static const _keyHost = 'server_host';
  static const _keyPort = 'server_port';
  static const _keyInputMode = 'input_mode';
  static const _keyOutputMode = 'output_mode';
  static const defaultHost = '192.168.1.100';
  static const defaultPort = 8080;

  String _host = defaultHost;
  int _port = defaultPort;
  InputMode _inputMode = InputMode.voice;
  OutputMode _outputMode = OutputMode.voice;
  bool _loaded = false;

  String get host => _host;
  int get port => _port;
  InputMode get inputMode => _inputMode;
  OutputMode get outputMode => _outputMode;
  bool get useVoiceInput => _inputMode == InputMode.voice;
  bool get useVoiceOutput => _outputMode == OutputMode.voice;
  bool get isLoaded => _loaded;
  String get baseUrl => 'http://$_host:$_port';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_keyHost) ?? defaultHost;
    _port = prefs.getInt(_keyPort) ?? defaultPort;
    final modeStr = prefs.getString(_keyInputMode) ?? 'voice';
    _inputMode = modeStr == 'text' ? InputMode.text : InputMode.voice;
    final outStr = prefs.getString(_keyOutputMode) ?? 'voice';
    _outputMode = outStr == 'text' ? OutputMode.text : OutputMode.voice;
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

  Future<void> setInputMode(InputMode mode) async {
    if (_inputMode == mode) return;
    _inputMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInputMode, mode == InputMode.text ? 'text' : 'voice');
    notifyListeners();
  }

  Future<void> setOutputMode(OutputMode mode) async {
    if (_outputMode == mode) return;
    _outputMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOutputMode, mode == OutputMode.text ? 'text' : 'voice');
    notifyListeners();
  }
}
