import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/colors.dart';
import '../utils/transfer_config.dart';
import '../utils/image_fold.dart';

class MessageBox extends StatefulWidget {
  final Function(String) onSend;
  final Function(Uint8List)? onSendVoice;
  final Function(Uint8List)? onSendImage;
  final Function(String)? onSendLocation;

  const MessageBox({
    super.key,
    required this.onSend,
    this.onSendVoice,
    this.onSendImage,
    this.onSendLocation,
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
      final status = await Permission.microphone.request();
      if (status.isGranted && await _audioRecorder.hasPermission()) {
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

  Future<void> _handleAttachment() async {
    final textPrimary = AppColors.getTextPrimary(context);
    final subtitleColor = AppColors.getSubtitle(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.getCard(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: subtitleColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Share Over Mesh',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Optimized for rapid transmission over off-grid ESP-NOW',
                  style: TextStyle(fontSize: 12, color: subtitleColor),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 22),
                  ),
                  title: Text('Take Photo', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Text('Capture and compress for instant mesh transfer', style: TextStyle(color: subtitleColor, fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 4),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: AppColors.secondary, size: 22),
                  ),
                  title: Text('Photo Gallery', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Text('Select image folded to fit ~5s radio budget', style: TextStyle(color: subtitleColor, fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 4),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: AppColors.error, size: 22),
                  ),
                  title: Text('Share GPS Location', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Text('Broadcast your live offline coordinates', style: TextStyle(color: subtitleColor, fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(context);
                    _shareLocation();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One step: pick -> fold (automatic) -> send. The result is sized to arrive in ~5 seconds.
  Future<void> _pickImage(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (pickedFile == null || widget.onSendImage == null) return;
      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      FoldedImage folded;
      try {
        folded = await ImageFolder.fold(bytes);
      } finally {
        if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
      }

      messenger.showSnackBar(SnackBar(
        content: Text(
          'Sending ${folded.description} · ${(folded.bytes.length / 1024).toStringAsFixed(1)} KB · '
          '~${TransferConfig.estimateSeconds(folded.bytes.length)} s',
        ),
      ));
      widget.onSendImage!(folded.bytes);
    } catch (e) {
      debugPrint('Image pick error: $e');
      messenger.showSnackBar(SnackBar(content: Text('Could not send image: $e')));
    }
  }

  Future<void> _shareLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String msg) => messenger.showSnackBar(SnackBar(content: Text(msg)));
    String fmt(Position p) =>
        '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        say('Turn on device location (GPS) first.');
        await Geolocator.openLocationSettings();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        say('Location permission denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        say('Location permission is blocked. Enable it in app settings.');
        await Geolocator.openAppSettings();
        return;
      }

      say('Getting GPS fix…');
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        widget.onSendLocation?.call(fmt(pos));
      } on TimeoutException {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) {
          say('No GPS fix. Try near a window or outdoors.');
          return;
        }
        say('No live fix - sending last known location.');
        widget.onSendLocation?.call(fmt(last));
      }
    } catch (e) {
      debugPrint('Location error: $e');
      say('Location error: $e');
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(
          top: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Attachment button
            IconButton(
              tooltip: 'Attach Media or Location',
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: AppColors.primary,
                size: 26,
              ),
              onPressed: _handleAttachment,
            ),
            const SizedBox(width: 4),

            // Message Text Input Box
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _isRecording ? AppColors.error : cardBorder,
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  style: TextStyle(color: textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: _isRecording ? 'Recording voice note...' : 'Message mesh node...',
                    hintStyle: TextStyle(
                      color: _isRecording ? AppColors.error : subtitleColor,
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Push-To-Talk Microphone
            GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hold the mic button to record voice note'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _isRecording
                      ? AppColors.error
                      : AppColors.getCardBorder(context).withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isRecording ? Icons.mic : Icons.mic_none_rounded,
                  color: _isRecording ? Colors.white : textPrimary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Send Button
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.black,
                  size: 22,
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
