import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/model_manager.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _isSaving = false;
  bool _isDownloading = false;
  bool _modelChanged = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _hostController = TextEditingController(text: settings.host);
    _portController = TextEditingController(text: settings.port.toString());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (host.isEmpty) {
      _showError('Bitte einen Host eingeben.');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      _showError('Bitte einen gültigen Port eingeben (1–65535).');
      return;
    }

    setState(() => _isSaving = true);
    await context.read<SettingsService>().save(host, port);
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen gespeichert')),
      );
      Navigator.of(context).pop(_modelChanged);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  /// Show confirmation dialog, then download the model.
  Future<void> _confirmAndDownload(SttEngine engine, {VoskModelSize? voskSize, SherpaModelSize? sherpaSize}) async {
    final sizeLabel = ModelManager.downloadSizeLabel(engine, voskSize: voskSize, sherpaSize: sherpaSize);
    final engineName = switch (engine) {
      SttEngine.vosk => 'Vosk',
      SttEngine.sherpaOnnx => 'Whisper (Sherpa-ONNX)',
      SttEngine.platform => 'Platform',
    };

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modell herunterladen?'),
        content: Text(
          '$engineName-Modell herunterladen?\n\n'
          'Download-Größe: $sizeLabel\n\n'
          'Das Modell wird einmalig heruntergeladen und lokal gespeichert. '
          'Stelle sicher, dass du eine stabile Internetverbindung hast.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Herunterladen'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isDownloading = true);
    final mm = context.read<ModelManager>();
    final ok = await mm.downloadModel(engine, sherpaSize: sherpaSize, voskSize: voskSize);
    if (mounted) {
      setState(() => _isDownloading = false);
      if (ok) {
        _modelChanged = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modell erfolgreich heruntergeladen ✓')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download fehlgeschlagen: ${mm.error ?? "Unbekannter Fehler"}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Input mode section ---
          Text(
            'Eingabemodus',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Consumer<SettingsService>(
            builder: (context, settings, _) {
              return Column(
                children: [
                  _InputModeCard(
                    icon: Icons.mic,
                    title: 'Spracheingabe (PTT)',
                    subtitle: 'Gedrückt halten zum Sprechen',
                    selected: settings.inputMode == InputMode.voice,
                    onTap: () => settings.setInputMode(InputMode.voice),
                  ),
                  const SizedBox(height: 8),
                  _InputModeCard(
                    icon: Icons.keyboard,
                    title: 'Texteingabe',
                    subtitle: 'Funksprüche per Tastatur eingeben',
                    selected: settings.inputMode == InputMode.text,
                    onTap: () => settings.setInputMode(InputMode.text),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          // --- STT engine section (only visible in voice mode) ---
          Consumer<SettingsService>(
            builder: (context, settings, _) {
              if (settings.inputMode != InputMode.voice) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spracherkennung',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Änderung erfordert App-Neustart',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade300),
                  ),
                  const SizedBox(height: 8),
                  _InputModeCard(
                    icon: Icons.speed,
                    title: 'Vosk',
                    subtitle: 'Echtzeit-Streaming, offline, schnell',
                    selected: settings.sttEngine == SttEngine.vosk,
                    onTap: () => settings.setSttEngine(SttEngine.vosk),
                  ),
                  if (settings.sttEngine == SttEngine.vosk) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonFormField<VoskModelSize>(
                        initialValue: settings.voskModelSize,
                        decoration: const InputDecoration(
                          labelText: 'Vosk Modellgröße',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: VoskModelSize.values.map((size) {
                          final labels = {
                            VoskModelSize.small: 'Small (~45 MB) — schnell, weniger genau',
                            VoskModelSize.large: 'Large (~420 MB) — genauer, ⚠️ hoher RAM-Bedarf',
                          };
                          return DropdownMenuItem(
                            value: size,
                            child: Text(labels[size]!, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (size) {
                          if (size != null) settings.setVoskModelSize(size);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ModelDownloadButton(
                      engine: SttEngine.vosk,
                      voskSize: settings.voskModelSize,
                      isDownloading: _isDownloading,
                      onDownload: () => _confirmAndDownload(
                        SttEngine.vosk,
                        voskSize: settings.voskModelSize,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _InputModeCard(
                    icon: Icons.psychology,
                    title: 'Whisper (Sherpa-ONNX)',
                    subtitle: 'Höhere Genauigkeit, langsamer, größerer Download',
                    selected: settings.sttEngine == SttEngine.sherpaOnnx,
                    onTap: () => settings.setSttEngine(SttEngine.sherpaOnnx),
                  ),
                  if (settings.sttEngine == SttEngine.sherpaOnnx) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonFormField<SherpaModelSize>(
                        initialValue: settings.sherpaModelSize,
                        decoration: const InputDecoration(
                          labelText: 'Whisper Modellgröße',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: SherpaModelSize.values.map((size) {
                          final labels = {
                            SherpaModelSize.tiny: 'Tiny (~75 MB) — schnell, weniger genau',
                            SherpaModelSize.small: 'Small (~460 MB) — ausgewogen',
                            SherpaModelSize.medium: 'Medium (~1.5 GB) — beste Qualität, langsam',
                          };
                          return DropdownMenuItem(
                            value: size,
                            child: Text(labels[size]!, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (size) {
                          if (size != null) settings.setSherpaModelSize(size);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ModelDownloadButton(
                      engine: SttEngine.sherpaOnnx,
                      sherpaSize: settings.sherpaModelSize,
                      isDownloading: _isDownloading,
                      onDownload: () => _confirmAndDownload(
                        SttEngine.sherpaOnnx,
                        sherpaSize: settings.sherpaModelSize,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _InputModeCard(
                    icon: Icons.phone_android,
                    title: 'Platform STT',
                    subtitle: 'Geräte-Spracherkennung (Google), benötigt Internet',
                    selected: settings.sttEngine == SttEngine.platform,
                    onTap: () => settings.setSttEngine(SttEngine.platform),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
          // --- Output mode section ---
          Text(
            'Ausgabemodus',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Consumer<SettingsService>(
            builder: (context, settings, _) {
              return Column(
                children: [
                  _InputModeCard(
                    icon: Icons.volume_up,
                    title: 'Sprachausgabe',
                    subtitle: 'KI-Antworten werden vorgelesen — nutzt die Sprachausgabe des Geräts',
                    selected: settings.outputMode == OutputMode.voice,
                    onTap: () => settings.setOutputMode(OutputMode.voice),
                  ),
                  const SizedBox(height: 8),
                  _InputModeCard(
                    icon: Icons.text_fields,
                    title: 'Textausgabe',
                    subtitle: 'KI-Antworten nur als Text anzeigen',
                    selected: settings.outputMode == OutputMode.text,
                    onTap: () => settings.setOutputMode(OutputMode.text),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          // --- Radio filter section ---
          Text(
            'Funkeffekt',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Simuliert den Klang eines BOS-Funkgeräts bei der Sprachausgabe.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Consumer<SettingsService>(
            builder: (context, settings, _) {
              return Column(
                children: [
                  SwitchListTile(
                    title: const Text('Bandpassfilter (300–3000 Hz)'),
                    subtitle: const Text('Typischer Funk-Frequenzbereich'),
                    value: settings.radioFilterEnabled,
                    onChanged: (v) => settings.setRadioFilter(v),
                    secondary: const Icon(Icons.graphic_eq),
                  ),
                  SwitchListTile(
                    title: const Text('Weißes Rauschen'),
                    subtitle: Text('${settings.radioNoiseDb.round()} dB'),
                    value: settings.radioNoiseEnabled,
                    onChanged: (v) => settings.setRadioNoise(v),
                    secondary: const Icon(Icons.noise_aware),
                  ),
                  if (settings.radioNoiseEnabled)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Text('-60 dB', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: settings.radioNoiseDb,
                              min: -60.0,
                              max: -10.0,
                              divisions: 50,
                              label: '${settings.radioNoiseDb.round()} dB',
                              onChanged: (v) => settings.setRadioNoiseDb(v),
                            ),
                          ),
                          const Text('-10 dB', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          // --- Server section ---
          Text(
            'Serververbindung',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Verbindung zum BOSTrainer-Server konfigurieren:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host / IP-Adresse',
              hintText: 'z.B. 192.168.1.100',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: 'z.B. 8080',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.numbers),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}

class _InputModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _InputModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: selected
            ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// Shows download status and button for a model.
class _ModelDownloadButton extends StatelessWidget {
  final SttEngine engine;
  final VoskModelSize? voskSize;
  final SherpaModelSize? sherpaSize;
  final bool isDownloading;
  final VoidCallback onDownload;

  const _ModelDownloadButton({
    required this.engine,
    this.voskSize,
    this.sherpaSize,
    required this.isDownloading,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final mm = context.watch<ModelManager>();

    return FutureBuilder<bool>(
      future: mm.isModelAvailable(engine, voskSize: voskSize, sherpaSize: sherpaSize),
      builder: (context, snapshot) {
        final available = snapshot.data ?? false;

        if (isDownloading) {
          return Consumer<ModelManager>(
            builder: (context, mm, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    LinearProgressIndicator(value: mm.progress > 0 ? mm.progress : null),
                    const SizedBox(height: 4),
                    Text(
                      mm.progress > 0
                          ? 'Herunterladen... ${(mm.progress * 100).toInt()}%'
                          : 'Herunterladen...',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          );
        }

        final sizeLabel = ModelManager.downloadSizeLabel(
          engine,
          voskSize: voskSize,
          sherpaSize: sherpaSize,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                available ? Icons.check_circle : Icons.cloud_download,
                size: 20,
                color: available ? Colors.green : Colors.amber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  available
                      ? 'Modell heruntergeladen ($sizeLabel)'
                      : 'Modell nicht vorhanden ($sizeLabel)',
                  style: TextStyle(
                    fontSize: 13,
                    color: available ? Colors.green : Colors.amber,
                  ),
                ),
              ),
              if (!available)
                TextButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download'),
                ),
            ],
          ),
        );
      },
    );
  }
}
