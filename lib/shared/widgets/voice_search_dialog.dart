import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Dialog pencarian dengan suara yang responsif dan ringan (tanpa efek blur/glow).
class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog({super.key});

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog> with SingleTickerProviderStateMixin {
  late final stt.SpeechToText _speech;
  bool _isListening = false;
  String _words = '';
  String _statusText = 'Menghubungkan mikrofon...';
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.88,
      upperBound: 1.12,
    )..repeat(reverse: true);
    _initAndListen();
  }

  Future<void> _initAndListen() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'listening') {
            setState(() {
              _isListening = true;
              _statusText = 'Mendengarkan... Sebutkan lagu atau artis';
            });
          } else if (status == 'notListening' || status == 'done') {
            setState(() {
              _isListening = false;
              _statusText = _words.isEmpty ? 'Tidak ada suara terdeteksi' : 'Selesai mendengarkan';
            });
            if (_words.trim().isNotEmpty) {
              Future.delayed(const Duration(milliseconds: 400), () {
                if (mounted) Navigator.of(context).pop(_words.trim());
              });
            }
          }
        },
        onError: (err) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _statusText = 'Izin mikrofon diperlukan atau tidak tersedia';
          });
        },
      );

      if (available) {
        setState(() {
          _isListening = true;
          _statusText = 'Mendengarkan... Sebutkan lagu atau artis';
        });
        await _speech.listen(
          onResult: (result) {
            if (!mounted) return;
            setState(() {
              _words = result.recognizedWords;
            });
            if (result.finalResult && _words.trim().isNotEmpty) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) Navigator.of(context).pop(_words.trim());
              });
            }
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.search,
          ),
        );
      } else {
        if (!mounted) return;
        setState(() {
          _statusText = 'Pengenalan suara tidak aktif pada perangkat ini';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText = 'Gagal mengakses mikrofon: $e';
      });
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _isListening ? _pulseCtrl : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening ? scheme.primary : scheme.surfaceContainerHighest,
              ),
              child: Icon(
                _isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
                size: 34,
                color: _isListening ? Colors.white : scheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _words.isNotEmpty ? '"$_words"' : _statusText,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(
              fontWeight: _words.isNotEmpty ? FontWeight.w700 : FontWeight.w500,
              color: _words.isNotEmpty ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ucapkan judul lagu, nama penyanyi, atau genre',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        if (_words.isNotEmpty)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(_words.trim()),
            child: const Text('Cari'),
          ),
      ],
    );
  }
}
