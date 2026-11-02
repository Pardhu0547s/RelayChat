import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message.dart';
import '../utils/colors.dart';
import 'image_viewer.dart';

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

  Future<void> _openLocation(String latLng) async {
    // 1) geo: opens any installed map app (works with offline maps).
    // 2) Fallback to Google Maps in a browser (needs internet).
    final coords = latLng.trim();
    try {
      final geo = Uri.parse('geo:$coords?q=$coords');
      if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    try {
      final web = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(coords)}');
      if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No map app available. Coordinates: $coords')),
    );
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
        ? (isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2))
        : isOutgoing
            ? AppColors.getOutgoingBubble(context)
            : AppColors.getIncomingBubble(context);

    final textPrimary = isSos
        ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B))
        : isOutgoing && !isDark
            ? const Color(0xFF064E3B)
            : AppColors.getTextPrimary(context);

    final subtitleColor = isSos
        ? (isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C))
        : isOutgoing && !isDark
            ? const Color(0xFF059669)
            : AppColors.getSubtitle(context);

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isOutgoing ? 18 : 4),
            bottomRight: Radius.circular(isOutgoing ? 4 : 18),
          ),
          border: Border.all(
            color: isSos 
                ? Colors.redAccent.withValues(alpha: 0.6)
                : isOutgoing
                    ? AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.4)
                    : AppColors.getCardBorder(context),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSos) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'EMERGENCY SOS',
                    style: TextStyle(
                      color: isDark ? Colors.red.shade300 : Colors.red.shade800,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            if (isVoice)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: _togglePlay,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: textPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Voice Note',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${_formatDuration(_position)} / ${_formatDuration(_duration)}",
                          style: TextStyle(color: subtitleColor, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (isLocation)
              InkWell(
                onTap: () => _openLocation(message.text),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Shared Location',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              message.text,
                              style: TextStyle(color: subtitleColor, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (isImage)
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ImageViewerScreen(path: message.text)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Image.file(
                        File(message.text),
                        width: 210,
                        fit: BoxFit.fitWidth,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) =>
                            Icon(Icons.broken_image, size: 50, color: textPrimary),
                      ),
                      Container(
                        margin: const EdgeInsets.all(6),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.fullscreen_rounded, size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              )
            else
              Text(
                message.text,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == MessageStatus.delivered
                        ? Icons.done_all_rounded
                        : (message.status == MessageStatus.sending
                            ? Icons.access_time_rounded
                            : Icons.done_rounded),
                    size: 14,
                    color: isDark ? AppColors.primary : const Color(0xFF059669),
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
