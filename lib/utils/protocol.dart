import 'dart:typed_data';
import 'dart:convert';

class BinaryProtocol {
  static const int MAGIC_BYTE = 0x01;
  static const int HEADER_SIZE = 71;

  /// Encodes a voice chunk into a binary packet
  static Uint8List encodeVoiceChunk({
    required int ttl,
    required int hop,
    required String origin,
    required String receiver,
    required String via,
    required String voiceId,
    required int chunkIdx,
    required int totalChunks,
    required Uint8List payload,
  }) {
    final buffer = ByteData(HEADER_SIZE + payload.length);

    buffer.setUint8(0, MAGIC_BYTE);
    buffer.setUint8(1, ttl);
    buffer.setUint8(2, hop);

    _writeString(buffer, 3, origin, 16);
    _writeString(buffer, 19, receiver, 16);
    _writeString(buffer, 35, via, 16);
    _writeString(buffer, 51, voiceId, 16);

    buffer.setUint16(67, chunkIdx, Endian.little);
    buffer.setUint16(69, totalChunks, Endian.little);

    final result = buffer.buffer.asUint8List();
    result.setAll(HEADER_SIZE, payload);

    return result;
  }

  /// Parses a binary packet header
  static Map<String, dynamic>? decodeHeader(Uint8List packet) {
    if (packet.length < HEADER_SIZE) return null;
    if (packet[0] != MAGIC_BYTE) return null;

    final buffer = ByteData.sublistView(packet);

    return {
      'ttl': buffer.getUint8(1),
      'hop': buffer.getUint8(2),
      'origin': _readString(buffer, 3, 16),
      'receiver': _readString(buffer, 19, 16),
      'via': _readString(buffer, 35, 16),
      'voiceId': _readString(buffer, 51, 16),
      'chunkIdx': buffer.getUint16(67, Endian.little),
      'totalChunks': buffer.getUint16(69, Endian.little),
      'payload': packet.sublist(HEADER_SIZE),
    };
  }

  static void _writeString(ByteData buffer, int offset, String str, int maxLen) {
    final bytes = utf8.encode(str);
    for (int i = 0; i < maxLen; i++) {
      if (i < bytes.length) {
        buffer.setUint8(offset + i, bytes[i]);
      } else {
        buffer.setUint8(offset + i, 0); // null padding
      }
    }
  }

  static String _readString(ByteData buffer, int offset, int maxLen) {
    final bytes = <int>[];
    for (int i = 0; i < maxLen; i++) {
      final b = buffer.getUint8(offset + i);
      if (b == 0) break;
      bytes.add(b);
    }
    return utf8.decode(bytes);
  }
}
