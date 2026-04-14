import 'package:flutter/material.dart';
import '../models/evaluation.dart';

class EvaluationScreen extends StatelessWidget {
  final Evaluation evaluation;
  final String scenarioName;

  const EvaluationScreen({
    super.key,
    required this.evaluation,
    required this.scenarioName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Auswertung'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Overall score
          _OverallScoreCard(
            score: evaluation.overallScore,
            summary: evaluation.summary,
            scenarioName: scenarioName,
          ),
          const SizedBox(height: 16),

          // Tips
          if (evaluation.tips.isNotEmpty) ...[
            _TipsCard(tips: evaluation.tips),
            const SizedBox(height: 16),
          ],

          // Per-message scores
          if (evaluation.messages.isNotEmpty) ...[
            Text(
              'Einzelbewertungen',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            ...evaluation.messages.map((m) => _MessageScoreCard(score: m)),
          ],

          const SizedBox(height: 32),

          // Retry button
          Center(
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              icon: const Icon(Icons.replay),
              label: const Text('Zurück zur Szenario-Auswahl'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _OverallScoreCard extends StatelessWidget {
  final int score;
  final String summary;
  final String scenarioName;

  const _OverallScoreCard({
    required this.score,
    required this.summary,
    required this.scenarioName,
  });

  Color _scoreColor() {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.lightGreen;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(scenarioName,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 16),
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey.shade800,
                    color: _scoreColor(),
                  ),
                  Center(
                    child: Text(
                      '$score%',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _scoreColor(),
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(summary, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  final List<String> tips;

  const _TipsCard({required this.tips});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.shade900.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '💡 Tipps',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            ...tips.map(
              (tip) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(tip)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageScoreCard extends StatelessWidget {
  final MessageScore score;

  const _MessageScoreCard({required this.score});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: _ScoreBadge(score: score.score),
        title: Text(
          'Funkspruch ${score.number}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          score.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Original text
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('"${score.text}"',
                      style: const TextStyle(fontStyle: FontStyle.italic)),
                ),
                const SizedBox(height: 12),

                // Correct
                if (score.correct.isNotEmpty) ...[
                  _FeedbackSection(
                    icon: Icons.check_circle,
                    color: Colors.green,
                    title: 'Korrekt',
                    items: score.correct,
                  ),
                  const SizedBox(height: 8),
                ],

                // Improvements
                if (score.improvements.isNotEmpty) ...[
                  _FeedbackSection(
                    icon: Icons.tips_and_updates,
                    color: Colors.amber,
                    title: 'Verbesserungen',
                    items: score.improvements,
                  ),
                  const SizedBox(height: 8),
                ],

                // Errors
                if (score.errors.isNotEmpty) ...[
                  _FeedbackSection(
                    icon: Icons.error,
                    color: Colors.red,
                    title: 'Fehler',
                    items: score.errors,
                  ),
                  const SizedBox(height: 8),
                ],

                // Improved version
                if (score.improved.isNotEmpty && score.score < 100 && (score.improvements.isNotEmpty || score.errors.isNotEmpty)) ...[
                  const Text('✨ Verbesserter Funkspruch:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade900.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('"${score.improved}"'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;

  const _ScoreBadge({required this.score});

  Color _color() {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.lightGreen;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color().withValues(alpha: 0.2),
        border: Border.all(color: _color(), width: 2),
      ),
      child: Center(
        child: Text(
          '$score',
          style: TextStyle(
            color: _color(),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> items;

  const _FeedbackSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: 20, top: 2),
            child: Text('• $item'),
          ),
        ),
      ],
    );
  }
}
