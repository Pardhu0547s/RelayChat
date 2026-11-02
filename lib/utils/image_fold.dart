import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'jpeg_slim.dart';
import 'paper_codec.dart';
import 'transfer_config.dart';

class FoldedImage {
  final Uint8List bytes;
  final bool isPaper;
  final String description;
  FoldedImage(this.bytes, this.isPaper, this.description);
}

class _FoldArgs {
  final Uint8List gray;
  final int width;
  final int height;
  final int budget;
  _FoldArgs(this.gray, this.width, this.height, this.budget);
}

/// Runs in a background isolate so the UI never freezes. Returns null for non-paper images.
PaperFit? _foldPaperEntry(_FoldArgs a) {
  if (!PaperCodec.looksLikePaper(a.gray, a.width, a.height)) return null;
  return PaperCodec.fitToBudget(a.gray, a.width, a.height, a.budget);
}

/// One automatic step: "fold" whatever the user picked so it crosses LoRa in ~5 seconds.
///  - Page / note / sketch / whiteboard -> crisp 1-bit page (context-coded), sized to fit.
///  - Anything else (people, places)    -> small colour JPEG, sized to fit.
/// The receiving phone "unfolds" it automatically (see ChatProvider._saveForDisplay).
class ImageFolder {
  // (shorter side in px, JPEG quality), biggest first. The first one that fits wins,
  // then leftover bytes are spent on quality.
  static const List<int> _sides = [160, 144, 128, 120, 112, 104, 96, 88, 80, 72, 64, 56, 48];
  static const List<int> _qualities = [14, 15, 16, 16, 17, 18, 20, 22, 25, 28, 32, 36, 40];

  static Future<FoldedImage> fold(Uint8List imageBytes) async {
    final budget = TransferConfig.imageBudgetBytes;

    final gray = await PaperCodec.decodeGray(imageBytes);
    final paper = await compute(
      _foldPaperEntry,
      _FoldArgs(gray.pixels, gray.width, gray.height, budget),
    );
    if (paper != null) {
      return FoldedImage(paper.blob, true, 'page ${paper.width}×${paper.height}');
    }

    final jpeg = await _foldPhoto(imageBytes, budget);
    return FoldedImage(jpeg, false, 'photo');
  }

  /// JPEG from the phone's encoder, minus the ~490 bytes of colour profile / JFIF it adds.
  static Future<Uint8List> _compress(Uint8List src, int side, int quality) async {
    final out = await FlutterImageCompress.compressWithList(
      src,
      minWidth: side,
      minHeight: side,
      quality: quality,
      format: CompressFormat.jpeg,
    );
    return JpegSlim.strip(out);
  }

  static Future<Uint8List> _foldPhoto(Uint8List source, int budget) async {
    // Shrink once up front so the search below is quick.
    final base = await FlutterImageCompress.compressWithList(
      source,
      minWidth: _sides.first + 16,
      minHeight: _sides.first + 16,
      quality: 90,
      format: CompressFormat.jpeg,
    );

    for (int i = 0; i < _sides.length; i++) {
      var out = await _compress(base, _sides[i], _qualities[i]);
      if (out.length > budget) continue;

      // This size fits: spend any leftover bytes on a higher quality.
      for (final bump in const [8, 4]) {
        final better = await _compress(base, _sides[i], _qualities[i] + bump);
        if (better.length <= budget) {
          out = better;
          break;
        }
      }
      return out;
    }
    return _compress(base, _sides.last, _qualities.last); // smallest rung: best we can do
  }
}
