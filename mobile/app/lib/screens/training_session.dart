import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scenario.dart';
import '../models/session.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
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
  late final SttService _stt;
  final TtsService _tts = TtsService();
  bool _isLoading = true;
  bool _isSending = false;
  bool _isListening = false;
  bool _isTranscribing = false;
  bool _isSpeaking = false;
  String _partialText = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _stt = context.read<SttService>();
    _stt.addListener(_onSttChanged);
    _startSession();
    _initTts();
  }

  void _onSttChanged() {
    if (!mounted) return;
    setState(() {
      _isListening = _stt.isListening;
      _isTranscribing = _stt.isTranscribing;
      _partialText = _stt.currentText;
    });
  }

  Future<void> _initTts() async {
    await _tts.initialize();
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

  void _onPttStart() {
    if (!_stt.isInitialized || _isSending || _isSpeaking) return;
    _tts.stop();
    setState(() {
      _isSpeaking = false;
    });
    _stt.startListening();
  }

  Future<void> _onPttEnd() async {
    if (!_stt.isListening) return;

    final text = await _stt.stopListening();
    if (!mounted) return;

    if (text.trim().isNotEmpty) {
      _sendMessage(text.trim());
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.isEmpty || _session == null || _isSending) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', text: text));
      _isSending = true;
    });
    _textController.clear();

    try {
      final api = context.read<ApiService>();
      final result = await api.sendMessage(_session!.sessionId, text);

      if (result.evaluation != null) {
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

      // Speak AI reply if voice output is enabled
      if (result.reply.isNotEmpty &&
          mounted &&
          context.read<SettingsService>().useVoiceOutput) {
        final settings = context.read<SettingsService>();
        setState(() => _isSpeaking = true);
        try {
          if (settings.radioFilterEnabled || settings.radioNoiseEnabled) {
            await _tts.speakWithRadioEffect(
              result.reply,
              bandpassEnabled: settings.radioFilterEnabled,
              noiseEnabled: settings.radioNoiseEnabled,
              noiseDb: settings.radioNoiseDb,
            );
          } else {
            await _tts.speakDirect(result.reply);
          }
        } catch (_) {
          // TTS errors are non-fatal
        }
        if (mounted) setState(() => _isSpeaking = false);
      }
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
    _stt.removeListener(_onSttChanged);
    _textController.dispose();
    _tts.dispose();
    if (_session != null) {
      context.read<ApiService>().deleteSession(_session!.sessionId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useVoice = context.watch<SettingsService>().useVoiceInput;

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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Fehler: $_error', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() { _error = null; _isLoading = true; });
                            _startSession();
                          },
                          child: const Text('Erneut versuchen'),
                        ),
                      ],
                    ),
                  ),
                )
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
                    // Speaking indicator
                    if (_isSpeaking)
                      Container(
                        width: double.infinity,
                        color: Colors.blue.shade900.withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '🔊 KI spricht...',
                              style: TextStyle(fontSize: 13, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    // Input area — switches based on setting
                    if (useVoice)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade800),
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_stt.isInitialized)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange.shade300),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Sprachmodell wird geladen…',
                                        style: TextStyle(fontSize: 12, color: Colors.orange.shade300),
                                      ),
                                    ],
                                  ),
                                ),
                              PttButton(
                                onPressStart: _onPttStart,
                                onPressEnd: _onPttEnd,
                                isRecording: _isListening,
                                isTranscribing: _isTranscribing,
                                isDisabled: _isSending || _isTranscribing || _isSpeaking || !_stt.isInitialized,
                                partialText: _stt.supportsStreaming ? _partialText : null,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      _TextInputBar(
                        controller: _textController,
                        isSending: _isSending || _isSpeaking,
                        onSend: _sendMessage,
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

class _TextInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final ValueChanged<String> onSend;

  const _TextInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
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
