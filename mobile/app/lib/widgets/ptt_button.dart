import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Push-to-talk button widget.
/// Hold to record, release to send. Shows visual feedback during
/// recording, partial text for streaming engines, and a transcribing
/// indicator while non-streaming engines process audio.
class PttButton extends StatefulWidget {
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final bool isRecording;
  final bool isTranscribing;
  final bool isDisabled;
  final String? partialText;

  const PttButton({
    super.key,
    required this.onPressStart,
    required this.onPressEnd,
    this.isRecording = false,
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
    if (widget.isRecording && !old.isRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && old.isRecording) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Partial text from streaming STT
        if (widget.isRecording &&
            widget.partialText != null &&
            widget.partialText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.partialText!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.green.shade300,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
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
                  widget.isRecording
                      ? '🎙 Aufnahme...'
                      : widget.isDisabled
                          ? '⏳ Bitte warten...'
                          : 'Zum Sprechen gedrückt halten',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isRecording
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
                scale: widget.isRecording ? _pulseAnimation.value : 1.0,
                child: child,
              );
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isRecording
                    ? Colors.red.shade600
                    : widget.isTranscribing
                        ? Colors.amber.shade800
                        : widget.isDisabled
                            ? Colors.grey.shade700
                            : Colors.red.shade800,
                boxShadow: widget.isRecording
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
                      widget.isRecording ? Icons.mic : Icons.mic_none,
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
