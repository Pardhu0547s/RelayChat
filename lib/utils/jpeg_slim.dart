import 'dart:typed_data';

/// Removes everything a JPEG decoder does not need, without touching a single pixel.
///
/// Phone encoders add metadata that is useless over LoRa: Android embeds an ICC colour
/// profile (~474 bytes) plus a JFIF header, which in a 1.3 KB thumbnail was 37% of the
/// whole file. The result is still a normal JPEG that any decoder opens, so the receiving
/// phone needs no special handling.
///
/// Dropped: APP0..APP15 (JFIF, EXIF, ICC profile, ...) and COM (comment) segments.
/// Kept verbatim: SOF, DQT, DHT, DRI, and the SOS header with all image data.
/// Anything unexpected returns the input unchanged.
class JpegSlim {
  static Uint8List strip(Uint8List d) {
    if (d.length < 4 || d[0] != 0xFF || d[1] != 0xD8) return d;

    final out = BytesBuilder()..add([0xFF, 0xD8]);
    var i = 2;
    while (i + 4 <= d.length) {
      if (d[i] != 0xFF) return d; // malformed: leave it alone
      final marker = d[i + 1];
      if (marker == 0xFF) {
        i++; // fill byte
        continue;
      }
      if (marker == 0xDA) {
        // Start of scan: copy the SOS header, all entropy-coded data and EOI as-is.
        out.add(Uint8List.sublistView(d, i));
        return out.toBytes();
      }
      final length = (d[i + 2] << 8) | d[i + 3];
      final end = i + 2 + length;
      if (length < 2 || end > d.length) return d; // truncated: leave it alone
      final isMetadata = (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE;
      if (!isMetadata) out.add(Uint8List.sublistView(d, i, end));
      i = end;
    }
    return d; // never found the scan
  }
}
