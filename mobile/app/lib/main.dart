import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/settings_service.dart';
import 'screens/scenario_list.dart';
import 'screens/settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.load();
  runApp(BOSTrainerApp(settings: settings));
}

class BOSTrainerApp extends StatelessWidget {
  final SettingsService settings;

  const BOSTrainerApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SettingsService>.value(
      value: settings,
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return Provider<ApiService>(
            key: ValueKey(settings.baseUrl),
            create: (_) => ApiService(baseUrl: settings.baseUrl),
            dispose: (_, service) => service.dispose(),
            child: MaterialApp(
              title: 'BOSTrainer',
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.red.shade800,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
                appBarTheme: AppBarTheme(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                ),
              ),
              home: settings.isLoaded
                  ? const ScenarioListScreen()
                  : const _InitialSettingsScreen(),
              debugShowCheckedModeBanner: false,
            ),
          );
        },
      ),
    );
  }
}

class _InitialSettingsScreen extends StatelessWidget {
  const _InitialSettingsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🚒 BOSTrainer')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
