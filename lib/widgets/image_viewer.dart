import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

/// Full-screen, zoomable view of a received/sent image with a Save-to-gallery button.
class ImageViewerScreen extends StatelessWidget {
  final String path;
  const ImageViewerScreen({super.key, required this.path});

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String msg) => messenger.showSnackBar(SnackBar(content: Text(msg)));

    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) {
          say('Gallery permission denied.');
          return;
        }
      }
      await Gal.putImage(path, album: 'RelayChat');
      say('Saved to gallery (RelayChat album).');
    } catch (e) {
      say('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Save to gallery',
            onPressed: () => _save(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 8,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high, // smoother upscaling of the small LoRa image
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image, size: 64, color: Colors.white54),
          ),
        ),
      ),
    );
  }
}
