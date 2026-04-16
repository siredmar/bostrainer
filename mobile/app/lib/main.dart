import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/model_manager.dart';
import 'services/settings_service.dart';
import 'services/stt_service.dart';
import 'screens/scenario_list.dart';
import 'screens/settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.load();
  final modelManager = ModelManager();
  final sttService = SttService(
    modelManager: modelManager,
    settings: settings,
  );
  runApp(BOSTrainerApp(
    settings: settings,
    modelManager: modelManager,
    sttService: sttService,
  ));
}

class BOSTrainerApp extends StatelessWidget {
  final SettingsService settings;
  final ModelManager modelManager;
  final SttService sttService;

  const BOSTrainerApp({
    super.key,
    required this.settings,
    required this.modelManager,
    required this.sttService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<ModelManager>.value(value: modelManager),
        ChangeNotifierProvider<SttService>.value(value: sttService),
      ],
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
                  ? const _HomeWithModelCheck()
                  : const _InitialSettingsScreen(),
              debugShowCheckedModeBanner: false,
            ),
          );
        },
      ),
    );
  }
}

/// Checks model availability and initializes STT, or shows appropriate status.
/// Does NOT block — shows scenario list while STT loads in background.
class _HomeWithModelCheck extends StatefulWidget {
  const _HomeWithModelCheck();

  @override
  State<_HomeWithModelCheck> createState() => _HomeWithModelCheckState();
}

class _HomeWithModelCheckState extends State<_HomeWithModelCheck> {
  bool _modelMissing = false;

  @override
  void initState() {
    super.initState();
    _initStt();
  }

  Future<void> _initStt() async {
    final stt = context.read<SttService>();
    final ok = await stt.initialize();

    if (!mounted) return;

    if (!ok && stt.modelMissing) {
      setState(() => _modelMissing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_modelMissing) {
      return _ModelMissingScreen(onRetry: () {
        setState(() => _modelMissing = false);
        _initStt();
      });
    }

    return const ScenarioListScreen();
  }
}

/// Shown when the selected STT model hasn't been downloaded yet.
class _ModelMissingScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _ModelMissingScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsService>();
    final engineName = switch (settings.sttEngine) {
      SttEngine.vosk => 'Vosk',
      SttEngine.sherpaOnnx => 'Whisper (Sherpa-ONNX)',
      SttEngine.platform => 'Platform',
    };
    final sizeLabel = ModelManager.downloadSizeLabel(
      settings.sttEngine,
      voskSize: settings.voskModelSize,
      sherpaSize: settings.sherpaModelSize,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('🚒 BOSTrainer')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_rounded, size: 48, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                'Sprachmodell benötigt',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Das $engineName-Modell ($sizeLabel) wurde noch nicht heruntergeladen.\n'
                'Bitte lade es in den Einstellungen herunter.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  if (result == true) onRetry();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Einstellungen öffnen'),
              ),
            ],
          ),
        ),
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
