import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
      Navigator.of(context).pop(true);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
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
                    subtitle: 'Gedrückt halten zum Sprechen — nutzt die Spracherkennung des Geräts',
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
