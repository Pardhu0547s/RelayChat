import 'dart:typed_data';
import 'dart:convert';

enum FrameType { text, ack, hello, voice, image, location, nack, unknown }

class Frame {
  static const int MAGIC_BYTE = 0xAA;
  static const int VERSION = 0x01;
  static const int HEADER_SIZE = 72;
  static const int MAX_PAYLOAD_SIZE = 1024; // Safe upper bound for BLE control frames

  final int version;
  final FrameType type;
  final int hop;
  final int ttl;
  final Uint8List origin;    // 16 bytes
  final Uint8List via;       // 16 bytes
  final Uint8List receiver;  // 16 bytes
  final Uint8List messageId; // 16 bytes
  final int rssi;
  final Uint8List payload;

  Frame({
    this.version = VERSION,
    required this.type,
    this.hop = 0,
    this.ttl = 8,
    required this.origin,
    required this.via,
    required this.receiver,
    required this.messageId,
    this.rssi = 0,
    required this.payload,
  }) {
    if (origin.length != 16) throw ArgumentError('Origin must be 16 bytes');
    if (via.length != 16) throw ArgumentError('Via must be 16 bytes');
    if (receiver.length != 16) throw ArgumentError('Receiver must be 16 bytes');
    if (messageId.length != 16) throw ArgumentError('MessageId must be 16 bytes');
    if (payload.length > MAX_PAYLOAD_SIZE) throw ArgumentError('Payload exceeds MAX_PAYLOAD_SIZE');
  }

  int get typeCode {
    switch (type) {
      case FrameType.text: return 0x00;
      case FrameType.ack: return 0x01;
      case FrameType.hello: return 0x02;
      case FrameType.voice: return 0x03;
      case FrameType.image: return 0x04;
      case FrameType.location: return 0x05;
      case FrameType.nack: return 0x06;
      default: return 0xFF;
    }
  }

  static FrameType typeFromCode(int code) {
    switch (code) {
      case 0x00: return FrameType.text;
      case 0x01: return FrameType.ack;
      case 0x02: return FrameType.hello;
      case 0x03: return FrameType.voice;
      case 0x04: return FrameType.image;
      case 0x05: return FrameType.location;
      case 0x06: return FrameType.nack;
      default: return FrameType.unknown;
    }
  }

  Uint8List encode() {
    final buffer = ByteData(HEADER_SIZE + payload.length);
    buffer.setUint8(0, MAGIC_BYTE);
    buffer.setUint8(1, version);
    buffer.setUint8(2, typeCode);
    buffer.setUint8(3, hop);
    buffer.setUint8(4, ttl);

    // Origin (16 bytes)
    for (int i = 0; i < 16; i++) buffer.setUint8(5 + i, origin[i]);
    // Via (16 bytes)
    for (int i = 0; i < 16; i++) buffer.setUint8(21 + i, via[i]);
    // Receiver (16 bytes)
    for (int i = 0; i < 16; i++) buffer.setUint8(37 + i, receiver[i]);
    // Message ID (16 bytes)
    for (int i = 0; i < 16; i++) buffer.setUint8(53 + i, messageId[i]);

    buffer.setUint16(69, payload.length, Endian.little);
    buffer.setInt8(71, rssi);

    final result = buffer.buffer.asUint8List();
    result.setAll(HEADER_SIZE, payload);
    return result;
  }

  static Frame? decode(Uint8List packet) {
    if (packet.length < HEADER_SIZE) return null;
    if (packet[0] != MAGIC_BYTE) return null;
    if (packet[1] != VERSION) return null;

    final buffer = ByteData.sublistView(packet);
    final payloadLength = buffer.getUint16(69, Endian.little);

    if (packet.length < HEADER_SIZE + payloadLength) return null; // Incomplete

    return Frame(
      version: buffer.getUint8(1),
      type: typeFromCode(buffer.getUint8(2)),
      hop: buffer.getUint8(3),
      ttl: buffer.getUint8(4),
      origin: packet.sublist(5, 21),
      via: packet.sublist(21, 37),
      receiver: packet.sublist(37, 53),
      messageId: packet.sublist(53, 69),
      rssi: buffer.getInt8(71),
      payload: packet.sublist(HEADER_SIZE, HEADER_SIZE + payloadLength),
    );
  }

  // Helpers for text payload conversion
  static Uint8List utf8ToBytes(String str) {
    return Uint8List.fromList(utf8.encode(str));
  }

  static String bytesToUtf8(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  // Helper for generating broadcast UUID
  static Uint8List getBroadcastUuid() {
    return Uint8List(16); // All zeros
  }

  static bool isBroadcast(Uint8List uuid) {
    for (int i = 0; i < 16; i++) {
      if (uuid[i] != 0) return false;
    }
    return true;
  }
}
