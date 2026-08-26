import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../utils/colors.dart';

class MessageBox extends StatefulWidget {
  final Function(String) onSend;
  final Function(Uint8List)? onSendVoice;

  const MessageBox({
    super.key,
    required this.onSend,
    this.onSendVoice,
  });

  @override
  State<MessageBox> createState() => _MessageBoxState();
}

class _MessageBoxState extends State<MessageBox> {
  final TextEditingController _controller = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  
  bool _isRecording = false;
  String? _recordPath;

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _recordPath = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc, // good compression
            bitRate: 16000, 
            sampleRate: 16000,
          ),
          path: _recordPath!,
        );
        setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      
      if (path != null && widget.onSendVoice != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          widget.onSendVoice!(bytes);
        }
      }
    } catch (e) {
      debugPrint('Error stopping record: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = AppColors.getCard(context);
    final inputBg = AppColors.getBackground(context);
    final textPrimary = AppColors.getTextPrimary(context);
    final subtitleColor = AppColors.getSubtitle(context);
    final cardBorder = AppColors.getCardBorder(context);
    final dividerColor = AppColors.getDivider(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(
          top: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Future File Sharing Placeholder (📎)
            IconButton(
              tooltip: 'Attach File (Future Feature)',
              icon: const Text(
                '📎',
                style: TextStyle(fontSize: 22),
              ),
              onPressed: () {
                 // Placeholder
              },
            ),
            const SizedBox(width: 4),

            // Message Text Input Box
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cardBorder, width: 1),
                ),
                child: TextField(
                  controller: _controller,
                  style: TextStyle(color: textPrimary),
                  decoration: InputDecoration(
                    hintText: _isRecording ? 'Recording...' : 'Message...',
                    hintStyle: TextStyle(color: _isRecording ? AppColors.error : subtitleColor),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Push-To-Talk Microphone (🎤)
            GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
              child: IconButton(
                tooltip: 'Push-To-Talk',
                icon: Icon(
                  Icons.mic,
                  color: _isRecording ? AppColors.error : textPrimary,
                  size: 26,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hold the mic button to record voice')),
                  );
                },
              ),
            ),
            const SizedBox(width: 4),

            // Send Button (➤)
            Container(
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.send_rounded,
                  color: Colors.black,
                  size: 20,
                ),
                onPressed: _handleSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
