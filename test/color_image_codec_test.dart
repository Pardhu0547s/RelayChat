import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_chat/utils/color_image_codec.dart';
import 'package:relay_chat/utils/paper_codec.dart';

Uint8List _sampleImage(int w, int h) {
  final px = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      px[o] = (x * 255 ~/ w);
      px[o + 1] = (y * 255 ~/ h);
      px[o + 2] = ((x + y) * 128 ~/ (w + h));
      px[o + 3] = 255;
    }
  }
  return px;
}

void main() {
  group('ColorImageCodec', () {
    test('pack and unpack round-trips correctly', () {
      final palette = Uint8List.fromList(List.generate(16 * 3, (i) => (i * 15) % 256));
      final indices = Uint8List.fromList(List.generate(40 * 30, (i) => i % 16));
      final bitmap = ColorImageBitmap(40, 30, palette, indices);

      final blob = ColorImageCodec.pack(bitmap);
      expect(ColorImageCodec.isColorImage(blob), isTrue);

      final unpacked = ColorImageCodec.unpack(blob)!;
      expect(unpacked.width, 40);
      expect(unpacked.height, 30);
      expect(unpacked.palette, palette);
      expect(unpacked.indices, indices);
    });

    test('quantizes synthetic image with dithering', () {
      final img = _sampleImage(100, 100);
      final bitmap = ColorImageCodec.quantize(img, 100, 100, 50, colors: 16, dither: true);

      expect(bitmap.width, 50);
      expect(bitmap.height, 50);
      expect(bitmap.colors, lessThanOrEqualTo(16));
      expect(bitmap.indices.every((v) => v < bitmap.colors), isTrue);
    });

    test('rejects invalid and non-color-image blobs', () {
      expect(ColorImageCodec.isColorImage(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), isFalse);
      expect(ColorImageCodec.isColorImage(PaperCodec.pack(PaperBitmap(10, 10, Uint8List(100)))), isFalse);
      expect(ColorImageCodec.unpack(Uint8List.fromList([0x04, 10, 0, 10, 0, 0])), isNull);
    });
  });
}
