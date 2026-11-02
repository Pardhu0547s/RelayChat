import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_chat/utils/color_paper_codec.dart';
import 'package:relay_chat/utils/paper_codec.dart';
import 'package:relay_chat/utils/transfer_config.dart';

/// Synthetic photo of a page under a warm lamp: brightness gradient + yellow tint,
/// with a red line, a blue line and a filled green box drawn on it.
Uint8List _colorPage(int w, int h) {
  final px = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = 150 + x * 90 / w; // uneven light
      var m = [1.0, 0.95, 0.8]; // warm tint of the paper
      var ink = [1.0, 1.0, 1.0];
      if (y >= 30 && y < 36 && x > 20 && x < w - 20) ink = [0.85, 0.2, 0.2]; // red pen
      if (x >= 50 && x < 56 && y > 20 && y < h - 20) ink = [0.2, 0.3, 0.85]; // blue pen
      if (x >= 200 && x < 240 && y >= 120 && y < 160) ink = [0.2, 0.75, 0.25]; // green fill
      final o = (y * w + x) * 4;
      for (int c = 0; c < 3; c++) {
        px[o + c] = (v * m[c] * ink[c]).round().clamp(0, 255);
      }
      px[o + 3] = 255;
    }
  }
  return px;
}

List<int> _rgbOf(ColorPaperBitmap bmp, int x, int y) {
  final p = bmp.indices[y * bmp.width + x] * 3;
  return [bmp.palette[p], bmp.palette[p + 1], bmp.palette[p + 2]];
}

void main() {
  group('ColorPaperCodec', () {
    test('pack/unpack round-trips exactly for 1, 2 and 4 bits per pixel', () {
      for (final k in [2, 3, 5, 16]) {
        final palette = Uint8List.fromList(List.generate(k * 3, (i) => (i * 37) % 256));
        final idx = Uint8List.fromList(List.generate(37 * 11, (i) => (i * 7) % k));
        final back = ColorPaperCodec.unpack(ColorPaperCodec.pack(ColorPaperBitmap(37, 11, palette, idx)))!;
        expect(back.width, 37);
        expect(back.height, 11);
        expect(back.palette, palette, reason: 'k=$k');
        expect(back.indices, idx, reason: 'k=$k');
      }
    });

    test('keeps pen colors, removes lamp tint and shading', () {
      final bmp = ColorPaperCodec.quantize(_colorPage(300, 200), 300, 200, 150, colors: 8);
      expect(bmp.width, 150);
      expect(bmp.height, 100);
      expect(bmp.palette.sublist(0, 3), [255, 255, 255]);

      // Paper on both the dim and bright side becomes pure white (index 0).
      expect(bmp.indices[5 * 150 + 2], 0);
      expect(bmp.indices[90 * 150 + 147], 0);

      final red = _rgbOf(bmp, 75, 16); // middle of the red line
      expect(red[0] > red[1] + 80 && red[0] > red[2] + 80, isTrue, reason: 'red=$red');
      final blue = _rgbOf(bmp, 26, 70); // middle of the blue line
      expect(blue[2] > blue[0] + 80, isTrue, reason: 'blue=$blue');
      final green = _rgbOf(bmp, 110, 70); // center of the filled green box
      expect(green[1] > green[0] + 60 && green[1] > green[2] + 60, isTrue, reason: 'green=$green');

      final inkCount = bmp.indices.where((v) => v != 0).length;
      expect(inkCount, lessThan(bmp.indices.length ~/ 5));
    });

    test('a colored sketch fits in a handful of LoRa packets', () {
      final blob = ColorPaperCodec.pack(ColorPaperCodec.quantize(_colorPage(600, 800), 600, 800, 320));
      expect(ColorPaperCodec.isColorPaper(blob), isTrue);
      expect(blob.length, lessThan(3000));
      expect(TransferConfig.packetsFor(blob.length), lessThanOrEqualTo(19));
    });

    test('a blank page gives a white-only palette', () {
      final px = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 200);
      final bmp = ColorPaperCodec.quantize(px, 64, 64, 64);
      expect(bmp.colors, 1);
      expect(bmp.indices.every((v) => v == 0), isTrue);
      expect(ColorPaperCodec.unpack(ColorPaperCodec.pack(bmp))!.colors, 1);
    });

    test('other formats and corrupt data are rejected', () {
      final bw = PaperCodec.pack(PaperBitmap(8, 8, Uint8List(64)));
      expect(ColorPaperCodec.isColorPaper(bw), isFalse);
      expect(PaperCodec.isPaper(Uint8List.fromList([0x03, 8, 0, 8, 0, 1, 255, 255, 255, 0])), isFalse);
      expect(ColorPaperCodec.isColorPaper(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0])), isFalse);
      expect(ColorPaperCodec.unpack(Uint8List.fromList([0x03, 8, 0, 8, 0, 0, 1, 2])), isNull); // 0 colors
      expect(ColorPaperCodec.unpack(Uint8List.fromList([0x03, 8, 0, 8, 0, 20, 1, 2])), isNull); // >16
      expect(ColorPaperCodec.unpack(Uint8List.fromList([0x03, 8, 0, 8, 0, 2, 1, 2, 3])), isNull); // truncated
      expect(ColorPaperCodec.unpack(Uint8List.fromList([0x03, 8, 0, 8, 0, 1, 255, 255, 255, 9, 9])), isNull);
    });
  });
}
