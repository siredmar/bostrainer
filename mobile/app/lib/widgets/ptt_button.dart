import 'package:flutter/material.dart';

/// Push-to-talk button widget.
/// In Phase 3, this will handle audio recording via sherpa-onnx.
/// Currently serves as a visual placeholder.
class PttButton extends StatelessWidget {
  final VoidCallback onPressed;

  const PttButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onPressed(),
      onLongPressEnd: (_) {
        // TODO Phase 3: stop recording, transcribe audio
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.shade700,
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 24),
      ),
    );
  }
}
