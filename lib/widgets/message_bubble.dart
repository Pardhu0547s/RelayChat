import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message.dart';
import '../utils/colors.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == MessageType.voice) {
      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });
      _audioPlayer.onDurationChanged.listen((newDuration) {
        if (mounted) {
          setState(() {
            _duration = newDuration;
          });
        }
      });
      _audioPlayer.onPositionChanged.listen((newPosition) {
        if (mounted) {
          setState(() {
            _position = newPosition;
          });
        }
      });
      _audioPlayer.setSourceDeviceFile(widget.message.text);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(widget.message.text));
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isOutgoing = message.isOutgoing;
    final formattedTime = DateFormat('hh:mm a').format(message.timestamp);
    final isDark = AppColors.isDark(context);

    final isSos = message.type == MessageType.sos;
    final isVoice = message.type == MessageType.voice;
    final isLocation = message.type == MessageType.location;
    final isImage = message.type == MessageType.image;

    final bg = isSos 
        ? Colors.redAccent.withValues(alpha: isDark ? 0.4 : 0.2)
        : isOutgoing
            ? AppColors.getOutgoingBubble(context)
            : AppColors.getIncomingBubble(context);

    final textPrimary = isSos
        ? (isDark ? Colors.red.shade200 : Colors.red.shade900)
        : isOutgoing && !isDark
            ? const Color(0xFF0F5132)
            : AppColors.getTextPrimary(context);

    final subtitleColor = isSos
        ? (isDark ? Colors.red.shade300 : Colors.red.shade700)
        : isOutgoing && !isDark
            ? const Color(0xFF198754)
            : AppColors.getSubtitle(context);

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
            bottomRight: Radius.circular(isOutgoing ? 4 : 16),
          ),
          border: Border.all(
            color: isSos 
                ? Colors.redAccent.withValues(alpha: 0.5)
                : isOutgoing
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.getCardBorder(context),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isVoice)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: textPrimary),
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(_position) + " / " + _formatDuration(_duration),
                    style: TextStyle(color: textPrimary, fontSize: 14),
                  ),
                ],
              )
            else if (isLocation)
              GestureDetector(
                onTap: () async {
                  final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${message.text}');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Location Shared',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              )
            else if (isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(message.text),
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.broken_image, size: 50, color: textPrimary),
                ),
              )
            else
              Text(
                message.text,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  height: 1.3,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 10,
                  ),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == MessageStatus.delivered
                        ? Icons.done_all
                        : (message.status == MessageStatus.sending ? Icons.access_time : Icons.done),
                    size: 13,
                    color: isDark ? AppColors.primary : const Color(0xFF198754),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
