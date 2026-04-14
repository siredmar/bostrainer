import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Push-to-talk button widget.
/// Hold to record, release to send. Shows visual feedback during recording
/// and a transcribing indicator while the engine finalizes.
class PttButton extends StatefulWidget {
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final bool isListening;
  final bool isTranscribing;
  final bool isDisabled;
  final String? partialText;

  const PttButton({
    super.key,
    required this.onPressStart,
    required this.onPressEnd,
    this.isListening = false,
    this.isTranscribing = false,
    this.isDisabled = false,
    this.partialText,
  });

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(PttButton old) {
    super.didUpdateWidget(old);
    if (widget.isListening && !old.isListening) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isListening && old.isListening) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  bool get _showPreview =>
      (widget.isListening || widget.isTranscribing) &&
      widget.partialText != null &&
      widget.partialText!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Partial transcription preview (visible during listening AND transcribing)
        if (_showPreview)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hearing, size: 16, color: Colors.amber.shade300),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.partialText!,
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Status text
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: widget.isTranscribing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Wird erkannt...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.amber.shade300,
                      ),
                    ),
                  ],
                )
              : Text(
                  widget.isListening
                      ? '🎙 Sprechen...'
                      : widget.isDisabled
                          ? '⏳ Bitte warten...'
                          : 'Zum Sprechen gedrückt halten',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isListening
                        ? Colors.red.shade300
                        : Colors.grey.shade500,
                  ),
                ),
        ),
        // The big PTT button
        GestureDetector(
          onLongPressStart: widget.isDisabled
              ? null
              : (_) {
                  HapticFeedback.mediumImpact();
                  widget.onPressStart();
                },
          onLongPressEnd: widget.isDisabled
              ? null
              : (_) {
                  HapticFeedback.lightImpact();
                  widget.onPressEnd();
                },
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: widget.isListening ? _pulseAnimation.value : 1.0,
                child: child,
              );
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isListening
                    ? Colors.red.shade600
                    : widget.isTranscribing
                        ? Colors.amber.shade800
                        : widget.isDisabled
                            ? Colors.grey.shade700
                            : Colors.red.shade800,
                boxShadow: widget.isListening
                    ? [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ]
                    : null,
              ),
              child: widget.isTranscribing
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Icon(
                      widget.isListening ? Icons.mic : Icons.mic_none,
                      color: widget.isDisabled
                          ? Colors.grey.shade500
                          : Colors.white,
                      size: 36,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
