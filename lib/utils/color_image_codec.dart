import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'paper_codec.dart';

/// An adaptive palette bitmap with index data for general photos and images.
class ColorImageBitmap {
  final int width;
  final int height;
  final Uint8List palette; // colors*3 bytes, RGB
  final Uint8List indices; // width*height palette indices
  ColorImageBitmap(this.width, this.height, this.palette, this.indices);

  int get colors => palette.length ~/ 3;
}

/// Universal codec for ANY color image (photos, scenery, people, UI, objects).
class ColorImageCodec {
  static const int kind = 0x04;
  static const int headerBytes = 6;
  static const int maxDimension = PaperCodec.maxDimension;
  static const int maxColors = 16;

  static bool isColorImage(Uint8List blob) => blob.length > headerBytes && blob[0] == kind;

  // ---------------------------------------------------------------------------
  // Pure functions (no dart:ui): easy to unit test.
  // ---------------------------------------------------------------------------

  /// Quantizes [rgba] (srcW*srcH*4) into a [targetWidth] dithered bitmap with [colors] palette.
  static ColorImageBitmap quantize(
    Uint8List rgba,
    int srcW,
    int srcH,
    int targetWidth, {
    int colors = 16,
    bool dither = true,
  }) {
    final k = colors.clamp(2, maxColors);
    final tw = math.max(1, math.min(targetWidth, srcW));
    final th = (srcH * tw / srcW).round().clamp(1, maxDimension);
    final n = tw * th;

    // 1) Downscale source RGBA to target dimensions
    final r = Float64List(n), g = Float64List(n), b = Float64List(n);
    for (int y = 0; y < th; y++) {
      final y0 = (y * srcH / th).round();
      var y1 = ((y + 1) * srcH / th).round();
      if (y1 <= y0) y1 = y0 + 1;
      for (int x = 0; x < tw; x++) {
        final x0 = (x * srcW / tw).round();
        var x1 = ((x + 1) * srcW / tw).round();
        if (x1 <= x0) x1 = x0 + 1;
        var sr = 0, sg = 0, sb = 0;
        for (int yy = y0; yy < y1; yy++) {
          var o = (yy * srcW + x0) * 4;
          for (int xx = x0; xx < x1; xx++, o += 4) {
            sr += rgba[o];
            sg += rgba[o + 1];
            sb += rgba[o + 2];
          }
        }
        final area = (y1 - y0) * (x1 - x0);
        final i = y * tw + x;
        r[i] = sr / area;
        g[i] = sg / area;
        b[i] = sb / area;
      }
    }

    // 2) K-means clustering over 12-bit color histogram
    final binCount = Int32List(4096);
    final binSum = Float64List(4096 * 3);
    int binOf(double rVal, double gVal, double bVal) {
      final ir = rVal.round().clamp(0, 255) >> 4;
      final ig = gVal.round().clamp(0, 255) >> 4;
      final ib = bVal.round().clamp(0, 255) >> 4;
      return (ir << 8) | (ig << 4) | ib;
    }

    for (int i = 0; i < n; i++) {
      final bin = binOf(r[i], g[i], b[i]);
      binCount[bin]++;
      binSum[bin * 3] += r[i];
      binSum[bin * 3 + 1] += g[i];
      binSum[bin * 3 + 2] += b[i];
    }

    final binIds = <int>[];
    final pts = <List<double>>[];
    final wts = <double>[];
    for (int bin = 0; bin < 4096; bin++) {
      final c = binCount[bin];
      if (c == 0) continue;
      binIds.add(bin);
      pts.add([binSum[bin * 3] / c, binSum[bin * 3 + 1] / c, binSum[bin * 3 + 2] / c]);
      wts.add(math.sqrt(c));
    }

    double dist2(List<double> p1, List<double> p2) {
      final dr = p1[0] - p2[0], dg = p1[1] - p2[1], db = p1[2] - p2[2];
      return dr * dr + dg * dg + db * db;
    }

    final minCount = math.max(1, n ~/ 2000);
    var cands = <int>[for (int p = 0; p < pts.length; p++) if (binCount[binIds[p]] >= minCount) p];
    if (cands.isEmpty) cands = List<int>.generate(pts.length, (p) => p);

    final centers = <List<double>>[List<double>.from(pts[cands.first])];
    final minD = List<double>.generate(cands.length, (s) => dist2(pts[cands[s]], centers[0]));
    final clusterCount = math.min(k, cands.length);
    while (centers.length < clusterCount) {
      var far = 0;
      for (int s = 1; s < cands.length; s++) {
        if (minD[s] > minD[far]) far = s;
      }
      if (minD[far] < 1) break;
      final c = List<double>.from(pts[cands[far]]);
      centers.add(c);
      for (int s = 0; s < cands.length; s++) {
        minD[s] = math.min(minD[s], dist2(pts[cands[s]], c));
      }
    }

    int nearest(List<double> p) {
      var best = 0;
      var bestD = dist2(p, centers[0]);
      for (int c = 1; c < centers.length; c++) {
        final d = dist2(p, centers[c]);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      return best;
    }

    for (int iter = 0; iter < 12; iter++) {
      final sum = List.generate(centers.length, (_) => [0.0, 0.0, 0.0, 0.0]);
      for (int p = 0; p < pts.length; p++) {
        final s = sum[nearest(pts[p])];
        s[0] += pts[p][0] * wts[p];
        s[1] += pts[p][1] * wts[p];
        s[2] += pts[p][2] * wts[p];
        s[3] += wts[p];
      }
      var moved = false;
      for (int c = 0; c < centers.length; c++) {
        if (sum[c][3] == 0) continue;
        final nc = [sum[c][0] / sum[c][3], sum[c][1] / sum[c][3], sum[c][2] / sum[c][3]];
        if (dist2(nc, centers[c]) > 0.25) moved = true;
        centers[c] = nc;
      }
      if (!moved) break;
    }

    final palBuilder = BytesBuilder();
    final palList = <List<double>>[];
    for (int c = 0; c < centers.length; c++) {
      final pr = centers[c][0].round().clamp(0, 255);
      final pg = centers[c][1].round().clamp(0, 255);
      final pb = centers[c][2].round().clamp(0, 255);
      palBuilder.add([pr, pg, pb]);
      palList.add([pr.toDouble(), pg.toDouble(), pb.toDouble()]);
    }
    final paletteBytes = palBuilder.toBytes();

    // 3) Map pixels to palette indices (with optional Floyd-Steinberg Dithering)
    final indices = Uint8List(n);
    if (!dither) {
      for (int i = 0; i < n; i++) {
        indices[i] = nearest([r[i], g[i], b[i]]);
      }
    } else {
      final curR = Float64List.fromList(r);
      final curG = Float64List.fromList(g);
      final curB = Float64List.fromList(b);

      for (int y = 0; y < th; y++) {
        for (int x = 0; x < tw; x++) {
          final i = y * tw + x;
          final pxColor = [curR[i].clamp(0.0, 255.0), curG[i].clamp(0.0, 255.0), curB[i].clamp(0.0, 255.0)];
          final idx = nearest(pxColor);
          indices[i] = idx;

          final chosen = palList[idx];
          final errR = pxColor[0] - chosen[0];
          final errG = pxColor[1] - chosen[1];
          final errB = pxColor[2] - chosen[2];

          void addError(int nx, int ny, double factor) {
            if (nx >= 0 && nx < tw && ny >= 0 && ny < th) {
              final ni = ny * tw + nx;
              curR[ni] += errR * factor;
              curG[ni] += errG * factor;
              curB[ni] += errB * factor;
            }
          }

          addError(x + 1, y, 7 / 16);
          addError(x - 1, y + 1, 3 / 16);
          addError(x, y + 1, 5 / 16);
          addError(x + 1, y + 1, 1 / 16);
        }
      }
    }

    return ColorImageBitmap(tw, th, paletteBytes, indices);
  }

  static Uint8List pack(ColorImageBitmap bmp) {
    final k = bmp.colors;
    final stride = (bmp.width + 1) >> 1;
    final packed = Uint8List(stride * bmp.height);
    for (int y = 0; y < bmp.height; y++) {
      for (int x = 0; x < bmp.width; x++) {
        final v = bmp.indices[y * bmp.width + x] & 0x0F;
        if (v == 0) continue;
        packed[y * stride + (x >> 1)] |= (x & 1 == 0) ? (v << 4) : v;
      }
    }
    final deflated = ZLibCodec(level: 9, raw: true).encode(packed);
    final out = BytesBuilder()
      ..addByte(kind)
      ..addByte(bmp.width & 0xFF)
      ..addByte(bmp.width >> 8)
      ..addByte(bmp.height & 0xFF)
      ..addByte(bmp.height >> 8)
      ..addByte(k)
      ..add(bmp.palette)
      ..add(deflated);
    return out.toBytes();
  }

  /// Returns null if [blob] is not a valid color image blob.
  static ColorImageBitmap? unpack(Uint8List blob) {
    if (!isColorImage(blob)) return null;
    final w = blob[1] | (blob[2] << 8);
    final h = blob[3] | (blob[4] << 8);
    final k = blob[5];
    if (w < 1 || h < 1 || w > maxDimension || h > maxDimension) return null;
    if (k < 1 || k > maxColors) return null;
    final dataStart = headerBytes + k * 3;
    if (blob.length <= dataStart) return null;
    try {
      final packed = ZLibCodec(raw: true).decode(blob.sublist(dataStart));
      final stride = (w + 1) >> 1;
      if (packed.length < stride * h) return null;
      final indices = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final byte = packed[y * stride + (x >> 1)];
          final v = (x & 1 == 0) ? ((byte >> 4) & 0x0F) : (byte & 0x0F);
          if (v >= k) return null;
          indices[y * w + x] = v;
        }
      }
      return ColorImageBitmap(w, h, Uint8List.fromList(blob.sublist(headerBytes, dataStart)), indices);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // dart:ui parts (need the Flutter engine).
  // ---------------------------------------------------------------------------

  /// Fold: photo bytes (JPEG/PNG/...) -> ultra-compact dithered color image blob.
  static Future<Uint8List> encode(Uint8List imageBytes, {int width = 200, int colors = 16, bool dither = true}) async {
    final img = await PaperCodec.decodeRgba(imageBytes);
    return pack(quantize(img.rgba, img.width, img.height, width, colors: colors, dither: dither));
  }

  /// Unfold: palette bitmap -> smoothly upscaled PNG (default 2x).
  static Future<Uint8List> toPng(ColorImageBitmap bmp, {int scale = 2}) {
    final pixels = Uint8List(bmp.width * bmp.height * 4);
    for (int i = 0; i < bmp.indices.length; i++) {
      final p = bmp.indices[i] * 3;
      pixels[i * 4] = bmp.palette[p];
      pixels[i * 4 + 1] = bmp.palette[p + 1];
      pixels[i * 4 + 2] = bmp.palette[p + 2];
      pixels[i * 4 + 3] = 255;
    }
    return PaperCodec.rgbaToPng(pixels, bmp.width, bmp.height, scale: scale);
  }
}
