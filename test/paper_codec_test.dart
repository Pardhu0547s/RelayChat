import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_chat/utils/paper_codec.dart';
import 'package:relay_chat/utils/transfer_config.dart';

/// Synthetic "photo of a paper": brightness gradient (uneven light) + dark strokes.
Uint8List _page(int w, int h) {
  final g = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      var v = 140 + (x * 100 ~/ w); // 140..240 gradient, like a lamp on one side
      final onStroke = (y > 30 && y < 36 && x > 20 && x < w - 20) || (x > 50 && x < 55 && y > 20 && y < h - 20);
      if (onStroke) v = (v * 0.3).toInt();
      g[y * w + x] = v;
    }
  }
  return g;
}

void main() {
  group('PaperCodec', () {
    test('pack/unpack round-trips exactly', () {
      final ink = Uint8List.fromList(List.generate(37 * 11, (i) => (i * 7 % 5 == 0) ? 1 : 0));
      final bmp = PaperBitmap(37, 11, ink);
      final back = PaperCodec.unpack(PaperCodec.pack(bmp))!;
      expect(back.width, 37);
      expect(back.height, 11);
      expect(back.ink, ink);
    });

    test('adaptive threshold keeps strokes despite uneven lighting', () {
      final bmp = PaperCodec.binarize(_page(300, 200), 300, 200, 150);
      expect(bmp.width, 150);
      expect(bmp.height, 100);
      final inkCount = bmp.ink.where((v) => v == 1).length;
      // strokes found, but the shaded half of the page is NOT turned into ink
      expect(inkCount, greaterThan(100));
      expect(inkCount, lessThan(bmp.ink.length ~/ 6));
    });

    test('a mostly-blank page compresses far below the photo budget', () {
      final blob = PaperCodec.pack(PaperCodec.binarize(_page(800, 1000), 800, 1000, 400));
      expect(PaperCodec.isPaper(blob), isTrue);
      expect(blob.length, lessThan(1200));
      expect(TransferConfig.packetsFor(blob.length), lessThanOrEqualTo(8));
    });

    test('photos and corrupt data are rejected', () {
      expect(PaperCodec.isPaper(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0])), isFalse);
      expect(PaperCodec.unpack(Uint8List.fromList([0x02, 10, 0, 10, 0, 9, 9, 9])), isNull);
      expect(PaperCodec.unpack(Uint8List.fromList([0x02, 0, 0, 0, 0, 1])), isNull);
    });
  });
}
