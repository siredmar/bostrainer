import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scenario.dart';
import '../models/session.dart';
import '../services/api_service.dart';
import '../widgets/ptt_button.dart';
import '../widgets/transcript_list.dart';
import 'evaluation.dart';

class TrainingSessionScreen extends StatefulWidget {
  final Scenario scenario;

  const TrainingSessionScreen({super.key, required this.scenario});

  @override
  State<TrainingSessionScreen> createState() => _TrainingSessionScreenState();
}

class _TrainingSessionScreenState extends State<TrainingSessionScreen> {
  Session? _session;
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession() async {
    try {
      final api = context.read<ApiService>();
      final session = await api.createSession(widget.scenario.key);
      setState(() {
        _session = session;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _session == null || _isSending) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', text: text.trim()));
      _isSending = true;
    });
    _textController.clear();

    try {
      final api = context.read<ApiService>();
      final result = await api.sendMessage(_session!.sessionId, text.trim());

      if (result.evaluation != null) {
        // "Ende" was detected — show evaluation
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EvaluationScreen(
              evaluation: result.evaluation!,
              scenarioName: widget.scenario.name,
            ),
          ),
        );
        return;
      }

      setState(() {
        if (result.reply.isNotEmpty) {
          _messages.add(ChatMessage(role: 'assistant', text: result.reply));
        }
        _isSending = false;
      });
    } catch (e) {
      setState(() {
        _isSending = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _endSession() async {
    if (_session == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sitzung beenden?'),
        content: const Text('Möchtest du die Sitzung beenden und die Auswertung erhalten?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Beenden'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final api = context.read<ApiService>();
      final evaluation = await api.endSession(_session!.sessionId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EvaluationScreen(
            evaluation: evaluation,
            scenarioName: widget.scenario.name,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    if (_session != null) {
      context.read<ApiService>().deleteSession(_session!.sessionId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scenario.name, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            onPressed: _messages.isEmpty ? null : _endSession,
            icon: const Icon(Icons.stop, color: Colors.white),
            label: const Text('Beenden', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Fehler: $_error'))
              : Column(
                  children: [
                    // Briefing card
                    if (_session != null && _messages.isEmpty)
                      _BriefingCard(session: _session!),
                    // Transcript
                    Expanded(
                      child: TranscriptList(
                        messages: _messages,
                        isTyping: _isSending,
                      ),
                    ),
                    // Input area
                    _InputBar(
                      controller: _textController,
                      isSending: _isSending,
                      onSend: _sendMessage,
                      onPtt: () {
                        // TODO: PTT recording - Phase 3
                      },
                    ),
                  ],
                ),
    );
  }
}

class _BriefingCard extends StatelessWidget {
  final Session session;

  const _BriefingCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      color: Colors.blue.shade900.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📋 Briefing',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(session.briefing),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text('Du: ${session.userRole}')),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.smart_toy, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text('KI: ${session.aiRole}')),
              ],
            ),
            if (session.firstHint.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                session.firstHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.amber.shade300,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final ValueChanged<String> onSend;
  final VoidCallback onPtt;

  const _InputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onPtt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.shade800),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // PTT button (placeholder for Phase 3)
            PttButton(onPressed: onPtt),
            const SizedBox(width: 8),
            // Text input (for text-only mode)
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Funkspruch eingeben...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                onSubmitted: onSend,
                enabled: !isSending,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: isSending
                  ? null
                  : () => onSend(controller.text),
              icon: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
