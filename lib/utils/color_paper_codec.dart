import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'paper_codec.dart';

/// A colored paper / whiteboard / sketch reduced to a small palette.
/// Palette index 0 is always the paper (white).
class ColorPaperBitmap {
  final int width;
  final int height;
  final Uint8List palette; // colors*3 bytes, RGB
  final Uint8List indices; // width*height palette indices
  ColorPaperBitmap(this.width, this.height, this.palette, this.indices);

  int get colors => palette.length ~/ 3;
}

class ColorPaperCodec {
  static const int kind = 0x03;
  static const int headerBytes = 6;
  static const int maxDimension = PaperCodec.maxDimension;
  static const int maxColors = 16;

  /// How much darker than the paper a pixel must be to count as ink.
  static const double inkBias = 0.14;

  /// How saturated (after removing the light tint) a pixel must be to count as colored ink.
  static const double minSaturation = 0.30;

  /// Pushes palette colors away from white so faint pen strokes come out vivid.
  static const double contrastBoost = 1.2;

  /// Blocks darker than this fraction of the page's paper brightness are not paper.
  static const double pageRatio = 0.65;

  /// Max chromaticity difference (L1 of r,g,b shares) from the page's paper tint.
  static const double maxTintDiff = 0.08;

  /// Stricter ink rules off the page (desk, deep shadows) so wood grain / fabric
  /// texture does not eat the palette and the byte budget.
  static const double offPageInkBias = 0.30;
  static const double offPageMinSaturation = 0.45;

  static bool isColorPaper(Uint8List blob) => blob.length > headerBytes && blob[0] == kind;

  static int bitsFor(int colors) => colors <= 2 ? 1 : (colors <= 4 ? 2 : 4);

  // ---------------------------------------------------------------------------
  // Pure functions (no dart:ui): easy to unit test.
  // ---------------------------------------------------------------------------

  /// [rgba] is srcW*srcH*4 bytes. [colors] is the palette size including white (2..16).
  static ColorPaperBitmap quantize(
    Uint8List rgba,
    int srcW,
    int srcH,
    int targetWidth, {
    int colors = 8,
  }) {
    final k = colors.clamp(2, maxColors);
    final tw = math.max(1, math.min(targetWidth, srcW));
    final th = (srcH * tw / srcW).round().clamp(1, maxDimension);
    final n = tw * th;

    // 1) Area-average downscale.
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

    // 2) Paper color estimate on a coarse grid of blocks.
    final bs = math.max(8, tw ~/ 16);
    final gw = (tw + bs - 1) ~/ bs, gh = (th + bs - 1) ~/ bs;
    final bgR = Float64List(gw * gh), bgG = Float64List(gw * gh), bgB = Float64List(gw * gh);
    final bgL = Float64List(gw * gh);
    for (int by = 0; by < gh; by++) {
      for (int bx = 0; bx < gw; bx++) {
        final members = <int>[];
        for (int y = by * bs; y < math.min(th, (by + 1) * bs); y++) {
          for (int x = bx * bs; x < math.min(tw, (bx + 1) * bs); x++) {
            members.add(y * tw + x);
          }
        }
        // Paper = the bright end of the block (ink is sparse and dark/colored). Skip the
        // top 5% so glare and specular highlights (on wood, plastic, metal) don't count.
        members.sort((p, q) => _lum(r[q], g[q], b[q]).compareTo(_lum(r[p], g[p], b[p])));
        final from = members.length ~/ 20;
        final to = math.max(from + 1, members.length ~/ 4);
        var ar = 0.0, ag = 0.0, ab = 0.0;
        for (int t = from; t < to; t++) {
          final i = members[t];
          ar += r[i];
          ag += g[i];
          ab += b[i];
        }
        final top = to - from;
        final bi = by * gw + bx;
        bgR[bi] = ar / top;
        bgG[bi] = ag / top;
        bgB[bi] = ab / top;
        bgL[bi] = _lum(bgR[bi], bgG[bi], bgB[bi]);
      }
    }

    // Which blocks are paper? Bright enough compared with typical paper brightness,
    // AND same tint as brightest blocks.
    final nb = gw * gh;
    final sortedL = Float64List.fromList(bgL)..sort();
    final paperLevel = sortedL[((nb - 1) * 0.9).round()];
    List<double> chroma(int i) {
      final s = math.max(1.0, bgR[i] + bgG[i] + bgB[i]);
      return [bgR[i] / s, bgG[i] / s, bgB[i] / s];
    }

    final ref = [0.0, 0.0, 0.0];
    var refN = 0;
    for (int i = 0; i < nb; i++) {
      if (bgL[i] < paperLevel * 0.95) continue;
      final c = chroma(i);
      for (int ch = 0; ch < 3; ch++) {
        ref[ch] += c[ch];
      }
      refN++;
    }
    for (int ch = 0; ch < 3; ch++) {
      ref[ch] /= math.max(1, refN);
    }
    final isPaper = List<bool>.generate(nb, (i) {
      if (bgL[i] < paperLevel * pageRatio) return false;
      final c = chroma(i);
      return (c[0] - ref[0]).abs() + (c[1] - ref[1]).abs() + (c[2] - ref[2]).abs() < maxTintDiff;
    });

    final outside = Uint8List(nb);
    final queue = <int>[];
    for (int bi = 0; bi < nb; bi++) {
      final bx = bi % gw, by = bi ~/ gw;
      if (!isPaper[bi] && (bx == 0 || by == 0 || bx == gw - 1 || by == gh - 1)) {
        outside[bi] = 1;
        queue.add(bi);
      }
    }
    for (int q = 0; q < queue.length; q++) {
      final bi = queue[q];
      final bx = bi % gw, by = bi ~/ gw;
      for (final nbi in [
        if (bx > 0) bi - 1,
        if (bx < gw - 1) bi + 1,
        if (by > 0) bi - gw,
        if (by < gh - 1) bi + gw,
      ]) {
        if (!isPaper[nbi] && outside[nbi] == 0) {
          outside[nbi] = 1;
          queue.add(nbi);
        }
      }
    }

    final solid = List<bool>.generate(nb, (i) => isPaper[i]);
    while (true) {
      final newly = <int>[];
      for (int bi = 0; bi < nb; bi++) {
        if (solid[bi] || outside[bi] == 1) continue;
        final bx = bi % gw, by = bi ~/ gw;
        var cnt = 0;
        var ar = 0.0, ag = 0.0, ab = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final ny = by + dy, nx = bx + dx;
            if (ny < 0 || nx < 0 || ny >= gh || nx >= gw || !solid[ny * gw + nx]) continue;
            final j = ny * gw + nx;
            ar += bgR[j];
            ag += bgG[j];
            ab += bgB[j];
            cnt++;
          }
        }
        if (cnt == 0) continue;
        bgR[bi] = ar / cnt;
        bgG[bi] = ag / cnt;
        bgB[bi] = ab / cnt;
        bgL[bi] = _lum(bgR[bi], bgG[bi], bgB[bi]);
        newly.add(bi);
      }
      if (newly.isEmpty) break;
      for (final bi in newly) {
        solid[bi] = true;
      }
    }

    // 3) Divide out paper color and classify ink.
    final fr = Uint8List(n), fg = Uint8List(n), fb = Uint8List(n);
    final ink = Uint8List(n);
    for (int y = 0; y < th; y++) {
      final cy = ((y + 0.5) / bs - 0.5).clamp(0.0, (gh - 1).toDouble());
      final y0 = cy.floor(), y1 = math.min(gh - 1, y0 + 1);
      final wy = cy - y0;
      for (int x = 0; x < tw; x++) {
        final cx = ((x + 0.5) / bs - 0.5).clamp(0.0, (gw - 1).toDouble());
        final x0 = cx.floor(), x1 = math.min(gw - 1, x0 + 1);
        final wx = cx - x0;
        double lerp(Float64List a) {
          final top = a[y0 * gw + x0] * (1 - wx) + a[y0 * gw + x1] * wx;
          final bot = a[y1 * gw + x0] * (1 - wx) + a[y1 * gw + x1] * wx;
          return math.max(40.0, top * (1 - wy) + bot * wy);
        }

        final i = y * tw + x;
        final pr = math.min(255.0, r[i] * 255 / lerp(bgR));
        final pg = math.min(255.0, g[i] * 255 / lerp(bgG));
        final pb = math.min(255.0, b[i] * 255 / lerp(bgB));
        fr[i] = pr.round();
        fg[i] = pg.round();
        fb[i] = pb.round();
        final mx = math.max(pr, math.max(pg, pb));
        final mn = math.min(pr, math.min(pg, pb));
        final sat = mx <= 0 ? 0.0 : (mx - mn) / mx;
        final off = outside[(y ~/ bs) * gw + (x ~/ bs)] == 1;
        final bias = off ? offPageInkBias : inkBias;
        final minSat = off ? offPageMinSaturation : minSaturation;
        if (_lum(pr, pg, pb) < 255 * (1 - bias) || sat > minSat) ink[i] = 1;
      }
    }

    final clean = Uint8List.fromList(ink);
    for (int y = 0; y < th; y++) {
      for (int x = 0; x < tw; x++) {
        if (ink[y * tw + x] == 0) continue;
        var neighbors = 0;
        for (int dy = -1; dy <= 1 && neighbors == 0; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final ny = y + dy, nx = x + dx;
            if (ny >= 0 && nx >= 0 && ny < th && nx < tw && ink[ny * tw + nx] == 1) {
              neighbors++;
              break;
            }
          }
        }
        if (neighbors == 0) clean[y * tw + x] = 0;
      }
    }

    // 4) Palette: weighted k-means.
    final inkIdx = <int>[];
    for (int i = 0; i < n; i++) {
      if (clean[i] == 1) inkIdx.add(i);
    }
    final indices = Uint8List(n); // 0 = paper
    if (inkIdx.isEmpty) {
      return ColorPaperBitmap(tw, th, Uint8List.fromList([255, 255, 255]), indices);
    }

    final binCount = Int32List(4096);
    final binSum = Float64List(4096 * 3);
    int binOf(int i) => ((fr[i] >> 4) << 8) | ((fg[i] >> 4) << 4) | (fb[i] >> 4);
    for (final i in inkIdx) {
      final bin = binOf(i);
      binCount[bin]++;
      binSum[bin * 3] += fr[i];
      binSum[bin * 3 + 1] += fg[i];
      binSum[bin * 3 + 2] += fb[i];
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

    double d2(List<double> a, List<double> b) {
      final dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
      return dr * dr + dg * dg + db * db;
    }

    final minCount = math.max(2, inkIdx.length ~/ 1000);
    var cand = <int>[for (int p = 0; p < pts.length; p++) if (binCount[binIds[p]] >= minCount) p];
    if (cand.isEmpty) cand = List<int>.generate(pts.length, (p) => p);
    var darkest = cand.first;
    for (final p in cand) {
      if (_lum(pts[p][0], pts[p][1], pts[p][2]) < _lum(pts[darkest][0], pts[darkest][1], pts[darkest][2])) {
        darkest = p;
      }
    }
    final clusters = math.min(k - 1, cand.length);
    final centers = <List<double>>[List<double>.from(pts[darkest])];
    final minD = List<double>.generate(cand.length, (s) => d2(pts[cand[s]], centers[0]));
    while (centers.length < clusters) {
      var far = 0;
      for (int s = 1; s < cand.length; s++) {
        if (minD[s] > minD[far]) far = s;
      }
      if (minD[far] < 1) break;
      final c = List<double>.from(pts[cand[far]]);
      centers.add(c);
      for (int s = 0; s < cand.length; s++) {
        minD[s] = math.min(minD[s], d2(pts[cand[s]], c));
      }
    }

    int nearest(List<double> p) {
      var best = 0;
      var bestD = d2(p, centers[0]);
      for (int c = 1; c < centers.length; c++) {
        final d = d2(p, centers[c]);
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      return best;
    }

    for (int iter = 0; iter < 15; iter++) {
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
        if (d2(nc, centers[c]) > 0.25) moved = true;
        centers[c] = nc;
      }
      if (!moved) break;
    }

    final binCluster = Int32List(4096);
    final used = List<int>.filled(centers.length, 0);
    for (int p = 0; p < pts.length; p++) {
      final c = nearest(pts[p]);
      binCluster[binIds[p]] = c;
      used[c] += binCount[binIds[p]];
    }
    final remap = List<int>.filled(centers.length, 0);
    final pal = BytesBuilder()..add([255, 255, 255]);
    var next = 1;
    for (int c = 0; c < centers.length; c++) {
      if (used[c] == 0) continue;
      remap[c] = next++;
      for (int ch = 0; ch < 3; ch++) {
        pal.addByte((255 - (255 - centers[c][ch]) * contrastBoost).round().clamp(0, 255));
      }
    }
    for (final i in inkIdx) {
      indices[i] = remap[binCluster[binOf(i)]];
    }
    return ColorPaperBitmap(tw, th, pal.toBytes(), indices);
  }

  static Uint8List pack(ColorPaperBitmap bmp) {
    final k = bmp.colors;
    final bits = bitsFor(k);
    final perByte = 8 ~/ bits;
    final stride = (bmp.width * bits + 7) >> 3;
    final packed = Uint8List(stride * bmp.height);
    for (int y = 0; y < bmp.height; y++) {
      for (int x = 0; x < bmp.width; x++) {
        final v = bmp.indices[y * bmp.width + x];
        if (v == 0) continue;
        packed[y * stride + x ~/ perByte] |= v << (8 - bits * (x % perByte + 1));
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

  /// Returns null if [blob] is not a valid color paper blob.
  static ColorPaperBitmap? unpack(Uint8List blob) {
    if (!isColorPaper(blob)) return null;
    final w = blob[1] | (blob[2] << 8);
    final h = blob[3] | (blob[4] << 8);
    final k = blob[5];
    if (w < 1 || h < 1 || w > maxDimension || h > maxDimension) return null;
    if (k < 1 || k > maxColors) return null;
    final dataStart = headerBytes + k * 3;
    if (blob.length <= dataStart) return null;
    try {
      final packed = ZLibCodec(raw: true).decode(blob.sublist(dataStart));
      final bits = bitsFor(k);
      final perByte = 8 ~/ bits;
      final mask = (1 << bits) - 1;
      final stride = (w * bits + 7) >> 3;
      if (packed.length < stride * h) return null;
      final indices = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final v = (packed[y * stride + x ~/ perByte] >> (8 - bits * (x % perByte + 1))) & mask;
          if (v >= k) return null;
          indices[y * w + x] = v;
        }
      }
      return ColorPaperBitmap(w, h, Uint8List.fromList(blob.sublist(headerBytes, dataStart)), indices);
    } catch (_) {
      return null;
    }
  }

  static double _lum(double r, double g, double b) => 0.299 * r + 0.587 * g + 0.114 * b;

  // ---------------------------------------------------------------------------
  // dart:ui parts (need the Flutter engine).
  // ---------------------------------------------------------------------------

  /// Fold: photo bytes (JPEG/PNG/...) -> compact color paper blob.
  static Future<Uint8List> encode(Uint8List imageBytes, {int width = 320, int colors = 8}) async {
    final img = await PaperCodec.decodeRgba(imageBytes);
    return pack(quantize(img.rgba, img.width, img.height, width, colors: colors));
  }

  /// Unfold: palette bitmap -> smoothly upscaled PNG (default 2x).
  static Future<Uint8List> toPng(ColorPaperBitmap bmp, {int scale = 2}) {
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
