import 'dart:convert';

enum MessageStatus { sending, sent, delivered, failed }
enum MessageType { text, ack, status, ping, voice, file, image, mesh, system, sos, unknown }

class ChatMessage {
  final int version;
  final String id;
  final DateTime timestamp;
  final MessageType type;
  final String origin;
  final String senderId;
  final String receiverId;
  final int hop;
  final int maxHop;
  final String text; // payload
  
  // Local UI state
  final bool isOutgoing;
  final bool isEncrypted;
  final MessageStatus status;

  ChatMessage({
    this.version = 1,
    required this.id,
    required this.timestamp,
    this.type = MessageType.text,
    required this.origin,
    required this.senderId,
    required this.receiverId,
    this.hop = 0,
    this.maxHop = 3,
    required this.text,
    required this.isOutgoing,
    this.isEncrypted = false,
    this.status = MessageStatus.delivered,
  });

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'type': type.name,
      'origin': origin,
      'sender': senderId,
      'receiver': receiverId,
      'hop': hop,
      'maxHop': maxHop,
      'payload': text,
    };
  }

  String toJson() => json.encode(toMap());

  factory ChatMessage.fromMap(Map<String, dynamic> map, {bool isOutgoing = false, MessageStatus status = MessageStatus.delivered}) {
    MessageType parsedType = MessageType.unknown;
    try {
      parsedType = MessageType.values.firstWhere((e) => e.name == map['type']);
    } catch (_) {}

    return ChatMessage(
      version: map['version']?.toInt() ?? 1,
      id: map['id'] ?? '',
      timestamp: map['timestamp'] != null 
          ? DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as int) * 1000)
          : DateTime.now(),
      type: parsedType,
      origin: map['origin'] ?? map['sender'] ?? '',
      senderId: map['sender'] ?? '',
      receiverId: map['receiver'] ?? '',
      hop: map['hop']?.toInt() ?? 0,
      maxHop: map['maxHop']?.toInt() ?? 3,
      text: map['payload'] ?? '',
      isOutgoing: isOutgoing,
      status: status,
    );
  }

  factory ChatMessage.fromJson(String source, {bool isOutgoing = false, MessageStatus status = MessageStatus.delivered}) =>
      ChatMessage.fromMap(json.decode(source), isOutgoing: isOutgoing, status: status);

  ChatMessage copyWith({
    int? version,
    String? id,
    DateTime? timestamp,
    MessageType? type,
    String? origin,
    String? senderId,
    String? receiverId,
    int? hop,
    int? maxHop,
    String? text,
    bool? isOutgoing,
    bool? isEncrypted,
    MessageStatus? status,
  }) {
    return ChatMessage(
      version: version ?? this.version,
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      origin: origin ?? this.origin,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      hop: hop ?? this.hop,
      maxHop: maxHop ?? this.maxHop,
      text: text ?? this.text,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      status: status ?? this.status,
    );
  }
}
