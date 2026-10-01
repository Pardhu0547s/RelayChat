import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/colors.dart';

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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.getCard(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                title: Text('Take Photo', style: TextStyle(color: AppColors.getTextPrimary(context))),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image, color: AppColors.secondary),
                title: Text('Gallery', style: TextStyle(color: AppColors.getTextPrimary(context))),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.location_on, color: AppColors.error),
                title: Text('Share Location', style: TextStyle(color: AppColors.getTextPrimary(context))),
                onTap: () {
                  Navigator.pop(context);
                  _shareLocation();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null && widget.onSendImage != null) {
        // Compress heavily for LoRa
        final bytes = await pickedFile.readAsBytes();
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 150,
          minHeight: 150,
          quality: 30, 
        );
        widget.onSendImage!(compressed);
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  Future<void> _shareLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (widget.onSendLocation != null) {
        widget.onSendLocation!('${position.latitude},${position.longitude}');
      }
    } catch (e) {
      debugPrint('Location error: $e');
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
            // Attachment button
            IconButton(
              tooltip: 'Attach File',
              icon: const Text(
                '📎',
                style: TextStyle(fontSize: 22),
              ),
              onPressed: _handleAttachment,
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
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Hold the mic button to record voice')),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.mic,
                  color: _isRecording ? AppColors.error : textPrimary,
                  size: 26,
                ),
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
