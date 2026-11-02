import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A paper / whiteboard / sketch, reduced to a crisp 1-bit (ink vs paper) bitmap.
class PaperBitmap {
  final int width;
  final int height;
  final Uint8List ink; // width*height values, 1 = ink, 0 = paper
  PaperBitmap(this.width, this.height, this.ink);
}

/// A folded page that fits the byte budget.
class PaperFit {
  final Uint8List blob;
  final int width;
  final int height;
  PaperFit(this.blob, this.width, this.height);
}

/// "Fold" a photo of a paper for LoRa and "unfold" it on the other side.
///
/// Fold:   grayscale -> area-average downscale -> adaptive (local) threshold -> 1 bit/pixel
///         -> JBIG-style context-modelling arithmetic coder.
///         The local threshold removes shadows and uneven lighting, so strokes stay sharp.
///         The coder predicts every pixel from the 12 already-known pixels around it, which
///         is ~35% smaller than deflate on pages, notes and sketches.
/// Unfold: arithmetic decode (lossless w.r.t. the folded bitmap) -> smooth 2x upscale -> PNG.
///
/// Blob layout: [0x02][width u16 LE][height u16 LE][arithmetic-coded pixels].
/// JPEG data starts with 0xFF, so a leading 0x02 can never be mistaken for a photo.
class PaperCodec {
  static const int kind = 0x02;
  static const int headerBytes = 5;
  static const int maxDimension = 1200;

  /// How much darker than the local average a pixel must be to count as ink.
  static const double inkBias = 0.12;

  /// Widths tried (largest first); the biggest one that fits the budget wins.
  static const List<int> widthLadder = [480, 440, 400, 360, 330, 300, 270, 240, 200, 160];

  static bool isPaper(Uint8List blob) => blob.length > headerBytes && blob[0] == kind;

  // ---------------------------------------------------------------------------
  // Pure functions (no dart:ui): run in an isolate and easy to unit test.
  // ---------------------------------------------------------------------------

  /// Area-average downscale of [gray] to [targetWidth] (never upscales).
  static PaperBitmapGray downscale(Uint8List gray, int srcW, int srcH, int targetWidth) {
    final tw = targetWidth < srcW ? targetWidth : srcW;
    final rawH = (srcH * tw / srcW).round();
    final th = rawH < 1 ? 1 : (rawH > maxDimension ? maxDimension : rawH);
    final big = _integral(gray, srcW, srcH);
    final stride = srcW + 1;
    final small = Uint8List(tw * th);
    for (int y = 0; y < th; y++) {
      final y0 = (y * srcH / th).round();
      var y1 = ((y + 1) * srcH / th).round();
      if (y1 <= y0) y1 = y0 + 1;
      for (int x = 0; x < tw; x++) {
        final x0 = (x * srcW / tw).round();
        var x1 = ((x + 1) * srcW / tw).round();
        if (x1 <= x0) x1 = x0 + 1;
        final sum = big[y1 * stride + x1] - big[y0 * stride + x1] -
            big[y1 * stride + x0] + big[y0 * stride + x0];
        small[y * tw + x] = sum ~/ ((y1 - y0) * (x1 - x0));
      }
    }
    return PaperBitmapGray(tw, th, small);
  }

  /// [gray] is srcW*srcH luminance (0 = black, 255 = white).
  static PaperBitmap binarize(Uint8List gray, int srcW, int srcH, int targetWidth) {
    final g = downscale(gray, srcW, srcH, targetWidth);
    final tw = g.width;
    final th = g.height;
    final small = g.pixels;

    // Adaptive threshold: ink = clearly darker than the local mean.
    final win = (tw ~/ 8) | 1;
    final r = win ~/ 2;
    final integ = _integral(small, tw, th);
    final stride = tw + 1;
    final ink = Uint8List(tw * th);
    for (int y = 0; y < th; y++) {
      final y0 = (y - r) < 0 ? 0 : y - r;
      final y1 = (y + r + 1) > th ? th : y + r + 1;
      for (int x = 0; x < tw; x++) {
        final x0 = (x - r) < 0 ? 0 : x - r;
        final x1 = (x + r + 1) > tw ? tw : x + r + 1;
        final sum = integ[y1 * stride + x1] - integ[y0 * stride + x1] -
            integ[y1 * stride + x0] + integ[y0 * stride + x0];
        final mean = sum / ((y1 - y0) * (x1 - x0));
        if (small[y * tw + x] < mean * (1 - inkBias)) ink[y * tw + x] = 1;
      }
    }
    return PaperBitmap(tw, th, ink);
  }

  /// Is this a photo of a page/sketch (flat background + dark strokes) rather than a scene?
  /// Pages have almost no pixels brighter than their surroundings; photos have many.
  static bool looksLikePaper(Uint8List gray, int srcW, int srcH) {
    final g = downscale(gray, srcW, srcH, 200);
    final w = g.width;
    final h = g.height;
    final r = ((w ~/ 8) | 1) ~/ 2;
    final integ = _integral(g.pixels, w, h);
    final stride = w + 1;
    var flat = 0, dark = 0, bright = 0;
    for (int y = 0; y < h; y++) {
      final y0 = (y - r) < 0 ? 0 : y - r;
      final y1 = (y + r + 1) > h ? h : y + r + 1;
      for (int x = 0; x < w; x++) {
        final x0 = (x - r) < 0 ? 0 : x - r;
        final x1 = (x + r + 1) > w ? w : x + r + 1;
        final sum = integ[y1 * stride + x1] - integ[y0 * stride + x1] -
            integ[y1 * stride + x0] + integ[y0 * stride + x0];
        final mean = sum / ((y1 - y0) * (x1 - x0));
        final ratio = g.pixels[y * w + x] / (mean < 1 ? 1 : mean);
        if ((ratio - 1).abs() < 0.08) flat++;
        if (ratio < 0.85) dark++;
        if (ratio > 1.15) bright++;
      }
    }
    final n = w * h;
    return bright / n <= 0.04 && flat / n >= 0.65 && dark / n >= 0.004 && dark / n <= 0.30;
  }

  static Uint8List pack(PaperBitmap bmp) {
    final coded = _Bilevel.encode(bmp.ink, bmp.width, bmp.height);
    final out = BytesBuilder()
      ..addByte(kind)
      ..addByte(bmp.width & 0xFF)
      ..addByte(bmp.width >> 8)
      ..addByte(bmp.height & 0xFF)
      ..addByte(bmp.height >> 8)
      ..add(coded);
    return out.toBytes();
  }

  /// Returns null if the header is not a valid paper blob.
  static PaperBitmap? unpack(Uint8List blob) {
    if (!isPaper(blob)) return null;
    final w = blob[1] | (blob[2] << 8);
    final h = blob[3] | (blob[4] << 8);
    if (w < 1 || h < 1 || w > maxDimension || h > maxDimension) return null;
    if (blob.length < headerBytes + 4) return null;
    try {
      return PaperBitmap(w, h, _Bilevel.decode(blob, headerBytes, w, h));
    } catch (_) {
      return null;
    }
  }

  /// Folds the page at the largest width whose blob is at most [budgetBytes].
  static PaperFit fitToBudget(Uint8List gray, int srcW, int srcH, int budgetBytes) {
    PaperFit attempt(int width) {
      final bmp = binarize(gray, srcW, srcH, width);
      return PaperFit(pack(bmp), bmp.width, bmp.height);
    }

    // Blob size grows with width, so binary-search the ladder (about 3-4 encodes).
    var lo = 0, hi = widthLadder.length - 1;
    PaperFit? best;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final fit = attempt(widthLadder[mid]);
      if (fit.blob.length <= budgetBytes) {
        best = fit;
        hi = mid - 1; // fits: try a wider one
      } else {
        lo = mid + 1;
      }
    }
    return best ?? attempt(widthLadder.last);
  }

  static Int32List _integral(Uint8List a, int w, int h) {
    final stride = w + 1;
    final out = Int32List((h + 1) * stride);
    for (int y = 0; y < h; y++) {
      var rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += a[y * w + x];
        out[(y + 1) * stride + (x + 1)] = out[y * stride + (x + 1)] + rowSum;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // dart:ui parts (need the Flutter engine).
  // ---------------------------------------------------------------------------

  /// Decodes any image to luminance (kept small: callers pass <= ~1024 px images).
  static Future<PaperBitmapGray> decodeGray(Uint8List imageBytes) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width;
      final h = image.height;
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
      final px = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final gray = Uint8List(w * h);
      for (int i = 0, o = 0; i < gray.length; i++, o += 4) {
        gray[i] = (px[o] * 299 + px[o + 1] * 587 + px[o + 2] * 114) ~/ 1000;
      }
      return PaperBitmapGray(w, h, gray);
    } finally {
      codec.dispose();
    }
  }

  /// Decodes any image (JPEG/PNG/...) to raw RGBA bytes.
  static Future<({Uint8List rgba, int width, int height})> decodeRgba(Uint8List imageBytes) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final result = (
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: image.width,
        height: image.height,
      );
      image.dispose();
      return result;
    } finally {
      codec.dispose();
    }
  }

  /// Raw RGBA pixels -> PNG, smoothly upscaled by [scale].
  static Future<Uint8List> rgbaToPng(Uint8List pixels, int width, int height, {int scale = 2}) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
    final src = await completer.future;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale.toDouble());
    canvas.drawImage(src, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.high);
    final picture = recorder.endRecording();
    final big = await picture.toImage(width * scale, height * scale);
    final data = await big.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    big.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }

  /// Unfold: bitmap -> smoothly upscaled PNG (default 2x) for display and saving.
  static Future<Uint8List> toPng(PaperBitmap bmp, {int scale = 2}) async {
    final pixels = Uint8List(bmp.width * bmp.height * 4);
    for (int i = 0; i < bmp.ink.length; i++) {
      final v = bmp.ink[i] == 1 ? 25 : 255;
      pixels[i * 4] = v;
      pixels[i * 4 + 1] = v;
      pixels[i * 4 + 2] = v;
      pixels[i * 4 + 3] = 255;
    }
    return rgbaToPng(pixels, bmp.width, bmp.height, scale: scale);
  }
}

/// Luminance image (0 = black, 255 = white).
class PaperBitmapGray {
  final int width;
  final int height;
  final Uint8List pixels;
  PaperBitmapGray(this.width, this.height, this.pixels);
}

// -----------------------------------------------------------------------------
// JBIG-style bilevel coder: adaptive binary arithmetic coding where each pixel's
// probability comes from a 12-pixel neighbourhood (3 from two rows up, 5 from the row
// above, 4 to the left). 16-bit probabilities, LZMA-style range coder.
// The Python reference used to validate this is mirrored by test/paper_codec_test.dart.
// -----------------------------------------------------------------------------
class _Bilevel {
  static const int _ctxBits = 12;
  static const int _limit = 1023; // halve counts above this: keeps the model adaptive

  static Int32List _offsets(int stride) => Int32List.fromList([
        -2 * stride - 1, -2 * stride, -2 * stride + 1,
        -stride - 2, -stride - 1, -stride, -stride + 1, -stride + 2,
        -4, -3, -2, -1,
      ]);

  /// P(bit == 0) as a 16-bit number from the counts seen in this context.
  static int _p0(int n0, int n1) {
    final p = ((n0 * 5 + 2) * 65536) ~/ ((n0 + n1) * 5 + 4);
    return p < 48 ? 48 : (p > 65488 ? 65488 : p);
  }

  static Uint8List encode(Uint8List ink, int w, int h) {
    final stride = w + 8; // 4 blank pixels left/right, 3 blank rows on top
    final padded = Uint8List(stride * (h + 3));
    final offs = _offsets(stride);
    final n0 = Uint16List(1 << _ctxBits);
    final n1 = Uint16List(1 << _ctxBits);
    final enc = _RangeEncoder();

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pos = (y + 3) * stride + x + 4;
        var ctx = 0;
        for (int k = 0; k < _ctxBits; k++) {
          ctx = (ctx << 1) | padded[pos + offs[k]];
        }
        final bit = ink[y * w + x];
        enc.encodeBit(_p0(n0[ctx], n1[ctx]), bit);
        if (bit == 1) {
          n1[ctx]++;
        } else {
          n0[ctx]++;
        }
        if (n0[ctx] + n1[ctx] > _limit) {
          n0[ctx] = (n0[ctx] + 1) >> 1;
          n1[ctx] = (n1[ctx] + 1) >> 1;
        }
        padded[pos] = bit;
      }
    }
    return enc.finish();
  }

  static Uint8List decode(Uint8List data, int start, int w, int h) {
    final stride = w + 8;
    final padded = Uint8List(stride * (h + 3));
    final offs = _offsets(stride);
    final n0 = Uint16List(1 << _ctxBits);
    final n1 = Uint16List(1 << _ctxBits);
    final dec = _RangeDecoder(data, start);
    final ink = Uint8List(w * h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pos = (y + 3) * stride + x + 4;
        var ctx = 0;
        for (int k = 0; k < _ctxBits; k++) {
          ctx = (ctx << 1) | padded[pos + offs[k]];
        }
        final bit = dec.decodeBit(_p0(n0[ctx], n1[ctx]));
        if (bit == 1) {
          n1[ctx]++;
        } else {
          n0[ctx]++;
        }
        if (n0[ctx] + n1[ctx] > _limit) {
          n0[ctx] = (n0[ctx] + 1) >> 1;
          n1[ctx] = (n1[ctx] + 1) >> 1;
        }
        padded[pos] = bit;
        ink[y * w + x] = bit;
      }
    }
    return ink;
  }
}

class _RangeEncoder {
  int _low = 0;
  int _range = 0xFFFFFFFF;
  int _cache = 0;
  int _cacheSize = 1;
  final BytesBuilder _out = BytesBuilder();

  void _shiftLow() {
    if (_low < 0xFF000000 || _low >= 0x100000000) {
      final carry = _low >> 32;
      var temp = _cache;
      do {
        _out.addByte((temp + carry) & 0xFF);
        temp = 0xFF;
        _cacheSize--;
      } while (_cacheSize != 0);
      _cache = (_low >> 24) & 0xFF;
    }
    _cacheSize++;
    _low = (_low & 0x00FFFFFF) << 8;
  }

  void encodeBit(int p0, int bit) {
    final bound = (_range >> 16) * p0;
    if (bit == 0) {
      _range = bound;
    } else {
      _low += bound;
      _range -= bound;
    }
    while (_range < 0x1000000) {
      _range = (_range << 8) & 0xFFFFFFFF;
      _shiftLow();
    }
  }

  Uint8List finish() {
    for (int i = 0; i < 5; i++) {
      _shiftLow();
    }
    final all = _out.toBytes();
    // The first byte is always 0, and the decoder reads zeros past the end,
    // so neither the first byte nor trailing zeros need to be sent.
    var end = all.length;
    while (end > 1 && all[end - 1] == 0) {
      end--;
    }
    return Uint8List.sublistView(all, 1, end);
  }
}

class _RangeDecoder {
  final Uint8List _data;
  int _pos;
  int _range = 0xFFFFFFFF;
  int _code = 0;

  _RangeDecoder(this._data, this._pos) {
    for (int i = 0; i < 4; i++) {
      _code = (_code << 8) | _next();
    }
  }

  int _next() {
    final v = _pos < _data.length ? _data[_pos] : 0;
    _pos++;
    return v;
  }

  int decodeBit(int p0) {
    final bound = (_range >> 16) * p0;
    int bit;
    if (_code < bound) {
      _range = bound;
      bit = 0;
    } else {
      _code -= bound;
      _range -= bound;
      bit = 1;
    }
    while (_range < 0x1000000) {
      _range = (_range << 8) & 0xFFFFFFFF;
      _code = ((_code << 8) | _next()) & 0xFFFFFFFF;
    }
    return bit;
  }
}
