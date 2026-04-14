import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scenario.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import 'settings.dart';
import 'training_session.dart';

class ScenarioListScreen extends StatefulWidget {
  const ScenarioListScreen({super.key});

  @override
  State<ScenarioListScreen> createState() => _ScenarioListScreenState();
}

class _ScenarioListScreenState extends State<ScenarioListScreen> {
  late Future<List<Scenario>> _scenariosFuture;

  @override
  void initState() {
    super.initState();
    _scenariosFuture = context.read<ApiService>().getScenarios();
  }

  void _refresh() {
    setState(() {
      _scenariosFuture = context.read<ApiService>().getScenarios();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚒 BOSTrainer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (changed == true) _refresh();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Scenario>>(
        future: _scenariosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Verbindung zum Server fehlgeschlagen',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            );
          }

          final scenarios = snapshot.data!;
          final grouped = _groupByCategory(scenarios);

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: grouped.length,
            itemBuilder: (context, index) {
              final category = grouped.keys.elementAt(index);
              final items = grouped[category]!;
              return _CategorySection(
                category: category,
                scenarios: items,
              );
            },
          );
        },
      ),
    );
  }

  Map<String, List<Scenario>> _groupByCategory(List<Scenario> scenarios) {
    final grouped = <String, List<Scenario>>{};
    for (final s in scenarios) {
      final cat = s.category.isNotEmpty ? s.category : 'Sonstiges';
      grouped.putIfAbsent(cat, () => []).add(s);
    }
    return grouped;
  }
}

class _CategorySection extends StatelessWidget {
  final String category;
  final List<Scenario> scenarios;

  const _CategorySection({required this.category, required this.scenarios});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            category,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.red.shade300,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...scenarios.map((s) => _ScenarioTile(scenario: s)),
        const Divider(),
      ],
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  final Scenario scenario;

  const _ScenarioTile({required this.scenario});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        scenario.isDemo ? Icons.headphones : Icons.radio,
        color: scenario.isDemo ? Colors.amber : Colors.red.shade400,
      ),
      title: Text(scenario.name),
      subtitle: Text(
        scenario.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TrainingSessionScreen(scenario: scenario),
          ),
        );
      },
    );
  }
}
