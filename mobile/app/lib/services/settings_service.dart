import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum InputMode { voice, text }
enum OutputMode { voice, text }

class SettingsService extends ChangeNotifier {
  static const _keyHost = 'server_host';
  static const _keyPort = 'server_port';
  static const _keyInputMode = 'input_mode';
  static const _keyOutputMode = 'output_mode';
  static const _keyRadioFilter = 'radio_filter';
  static const _keyRadioNoise = 'radio_noise';
  static const _keyRadioNoiseDb = 'radio_noise_db';
  static const defaultHost = '192.168.1.100';
  static const defaultPort = 8080;

  String _host = defaultHost;
  int _port = defaultPort;
  InputMode _inputMode = InputMode.voice;
  OutputMode _outputMode = OutputMode.voice;
  bool _radioFilterEnabled = true;
  bool _radioNoiseEnabled = true;
  double _radioNoiseDb = -35.0;
  bool _loaded = false;

  String get host => _host;
  int get port => _port;
  InputMode get inputMode => _inputMode;
  OutputMode get outputMode => _outputMode;
  bool get useVoiceInput => _inputMode == InputMode.voice;
  bool get useVoiceOutput => _outputMode == OutputMode.voice;
  bool get radioFilterEnabled => _radioFilterEnabled;
  bool get radioNoiseEnabled => _radioNoiseEnabled;
  double get radioNoiseDb => _radioNoiseDb;
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
    _radioFilterEnabled = prefs.getBool(_keyRadioFilter) ?? true;
    _radioNoiseEnabled = prefs.getBool(_keyRadioNoise) ?? true;
    _radioNoiseDb = prefs.getDouble(_keyRadioNoiseDb) ?? -35.0;
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

  Future<void> setRadioFilter(bool enabled) async {
    if (_radioFilterEnabled == enabled) return;
    _radioFilterEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRadioFilter, enabled);
    notifyListeners();
  }

  Future<void> setRadioNoise(bool enabled) async {
    if (_radioNoiseEnabled == enabled) return;
    _radioNoiseEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRadioNoise, enabled);
    notifyListeners();
  }

  Future<void> setRadioNoiseDb(double db) async {
    _radioNoiseDb = db;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyRadioNoiseDb, db);
    notifyListeners();
  }
}
