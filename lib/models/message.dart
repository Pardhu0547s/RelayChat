import 'dart:convert';

enum MessageStatus { sending, sent, delivered, failed }
enum MessageType { text, ack, status, ping, voice, file, image, mesh, system, unknown }

class ChatMessage {
  final int version;
  final String id;
  final DateTime timestamp;
  final MessageType type;
  final String senderId;
  final String receiverId;
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
    required this.senderId,
    required this.receiverId,
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
      'sender': senderId,
      'receiver': receiverId,
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
      senderId: map['sender'] ?? '',
      receiverId: map['receiver'] ?? '',
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
    String? senderId,
    String? receiverId,
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
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      status: status ?? this.status,
    );
  }
}
