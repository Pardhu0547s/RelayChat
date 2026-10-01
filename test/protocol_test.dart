import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_chat/utils/protocol.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('Binary Protocol Frame Tests', () {
    final uuid = const Uuid();
    late Uint8List origin;
    late Uint8List via;
    late Uint8List receiver;
    late Uint8List messageId;

    setUp(() {
      origin = uuid.v4obj().toBytes();
      via = uuid.v4obj().toBytes();
      receiver = uuid.v4obj().toBytes();
      messageId = uuid.v4obj().toBytes();
    });

    test('Encode and Decode Text Frame', () {
      final text = "Hello, World! This is a test message.";
      final payload = Frame.utf8ToBytes(text);

      final originalFrame = Frame(
        type: FrameType.text,
        hop: 1,
        ttl: 7,
        origin: origin,
        via: via,
        receiver: receiver,
        messageId: messageId,
        payload: payload,
      );

      final bytes = originalFrame.encode();
      expect(bytes.length, Frame.HEADER_SIZE + payload.length);
      expect(bytes[0], Frame.MAGIC_BYTE);
      expect(bytes[1], Frame.VERSION);
      expect(bytes[2], 0x00); // FrameType.text
      expect(bytes[3], 1);
      expect(bytes[4], 7);

      final decodedFrame = Frame.decode(bytes);
      expect(decodedFrame, isNotNull);
      expect(decodedFrame!.type, FrameType.text);
      expect(decodedFrame.hop, 1);
      expect(decodedFrame.ttl, 7);
      expect(decodedFrame.origin, origin);
      expect(decodedFrame.via, via);
      expect(decodedFrame.receiver, receiver);
      expect(decodedFrame.messageId, messageId);
      expect(Frame.bytesToUtf8(decodedFrame.payload), text);
    });

    test('Decode fails on incomplete frame', () {
      final frame = Frame(
        type: FrameType.text,
        origin: origin,
        via: via,
        receiver: receiver,
        messageId: messageId,
        payload: Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      final bytes = frame.encode();
      // Drop last 2 bytes
      final truncated = bytes.sublist(0, bytes.length - 2);
      
      expect(Frame.decode(truncated), isNull);
    });

    test('Decode handles max payload size', () {
      final payload = Uint8List(Frame.MAX_PAYLOAD_SIZE);
      for(int i=0; i<payload.length; i++) payload[i] = i % 256;

      final frame = Frame(
        type: FrameType.voice,
        origin: origin,
        via: via,
        receiver: receiver,
        messageId: messageId,
        payload: payload,
      );

      final bytes = frame.encode();
      final decoded = Frame.decode(bytes);

      expect(decoded, isNotNull);
      expect(decoded!.payload.length, Frame.MAX_PAYLOAD_SIZE);
      expect(decoded.payload, payload);
    });
    
    test('Throws on oversized payload', () {
      final payload = Uint8List(Frame.MAX_PAYLOAD_SIZE + 1);
      
      expect(() => Frame(
        type: FrameType.text,
        origin: origin,
        via: via,
        receiver: receiver,
        messageId: messageId,
        payload: payload,
      ), throwsArgumentError);
    });

    test('NACK frame round-trips with type code 0x06 and bitmap payload', () {
      final imageId = uuid.v4obj().toBytes();
      final bitmap = Uint8List.fromList([0xFF, 0x0F]); // chunks 0-11 received
      final payload = Uint8List.fromList([...imageId, ...bitmap]);

      final frame = Frame(
        type: FrameType.nack,
        origin: origin,
        via: via,
        receiver: receiver,
        messageId: messageId,
        payload: payload,
      );

      final bytes = frame.encode();
      expect(bytes[2], 0x06);

      final decoded = Frame.decode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.type, FrameType.nack);
      expect(decoded.payload.sublist(0, 16), imageId);
      expect(decoded.payload.sublist(16), bitmap);
    });
  });
}
