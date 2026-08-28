import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../shared/constants.dart';

/// زر الميكروفون — يفعّل/يوقف التعرّف على الكلام لتحويل الصوت إلى نص.
/// يختفي تلقائياً إذا كان الميكروفون غير متوفر على الجهاز.
class MicButton extends StatefulWidget {
  final stt.SpeechToText speech;
  final bool available;
  final String lang;
  final void Function(String text) onResult;

  const MicButton({
    super.key,
    required this.speech,
    required this.available,
    required this.lang,
    required this.onResult,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  bool _listening = false;

  /// يبدأ أو يوقف الاستماع الصوتي.
  Future<void> _toggle() async {
    if (!widget.available) return;
    if (_listening) {
      widget.speech.stop();
      if (mounted) setState(() => _listening = false);
    } else {
      final locale = widget.lang == 'ar' ? 'ar_SA' : 'en_US';
      if (!mounted) return;
      setState(() => _listening = true);
      try {
        await widget.speech.listen(
          localeId: locale,
          onResult: (result) {
            if (result.finalResult) {
              if (mounted) setState(() => _listening = false);
              widget.onResult(result.recognizedWords);
            }
          },
        );
      } catch (e) {
        debugPrint('Speech listen error: $e');
        if (mounted) setState(() => _listening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.available) return const SizedBox.shrink();
    return IconButton(
      icon: Icon(
        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: _listening ? AppColors.accent : AppColors.textSecondary,
      ),
      style: IconButton.styleFrom(
        backgroundColor: _listening
            ? AppColors.accent.withValues(alpha: 0.1)
            : Colors.transparent,
      ),
      onPressed: _toggle,
    );
  }
}
