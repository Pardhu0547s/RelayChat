import 'package:flutter/material.dart';
import '../utils/colors.dart';

class MessageBox extends StatefulWidget {
  final Function(String) onSend;

  const MessageBox({
    super.key,
    required this.onSend,
  });

  @override
  State<MessageBox> createState() => _MessageBoxState();
}

class _MessageBoxState extends State<MessageBox> {
  final TextEditingController _controller = TextEditingController();
  bool _isRecordingMock = false;

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  void _showFutureFeatureDialog(String featureName, String details) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.getCard(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.getCardBorder(context)),
        ),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              featureName,
              style: TextStyle(color: AppColors.getTextPrimary(context)),
            ),
          ],
        ),
        content: Text(
          details,
          style: TextStyle(color: AppColors.getTextSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Got It',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
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
                _showFutureFeatureDialog(
                  'Offline File Sharing',
                  'Space reserved for sending files, images, and voice notes via RelayChat Bluetooth/LoRa mesh network.',
                );
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
                    hintText: 'Message...',
                    hintStyle: TextStyle(color: subtitleColor),
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

            // Future Push-To-Talk Microphone Placeholder (🎤)
            GestureDetector(
              onLongPressStart: (_) {
                setState(() => _isRecordingMock = true);
              },
              onLongPressEnd: (_) {
                setState(() => _isRecordingMock = false);
                _showFutureFeatureDialog(
                  'Push-To-Talk (PTT)',
                  'Voice PTT transmission space reserved! Hold to talk functionality will stream raw audio frames over RelayChat.',
                );
              },
              child: IconButton(
                tooltip: 'Push-To-Talk (Future Feature)',
                icon: Text(
                  '🎤',
                  style: TextStyle(
                    fontSize: 22,
                    color: _isRecordingMock ? AppColors.error : null,
                  ),
                ),
                onPressed: () {
                  _showFutureFeatureDialog(
                    'Push-To-Talk (PTT)',
                    'Hold the mic button to transmit voice packets over offline mesh.',
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
