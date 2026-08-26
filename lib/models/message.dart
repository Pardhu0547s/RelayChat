import 'dart:convert';

enum MessageStatus { sending, sent, delivered, failed }
enum MessageType { text, ack, status, ping, voice, file, image, mesh, system, sos, hello, unknown }

class ChatMessage {
  final int version;
  final String id;
  final DateTime timestamp;
  final MessageType type;
  final String origin;
  final String via;
  final String receiverId;
  final int hop;
  final int ttl;
  final String text; // payload
  
  // Hello packet fields
  final String? senderName;
  final String? device;
  
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
    required this.via,
    required this.receiverId,
    this.hop = 0,
    this.ttl = 8,
    required this.text,
    this.senderName,
    this.device,
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
      'via': via,
      'receiver': receiverId,
      'hop': hop,
      'ttl': ttl,
      'payload': text,
      if (senderName != null) 'name': senderName,
      if (device != null) 'device': device,
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
      via: map['via'] ?? map['lastRelay'] ?? map['sender'] ?? '',
      receiverId: map['receiver'] ?? '',
      hop: map['hop']?.toInt() ?? 0,
      ttl: map['ttl']?.toInt() ?? 8,
      text: map['payload'] ?? '',
      senderName: map['name'],
      device: map['device'],
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
    String? via,
    String? receiverId,
    int? hop,
    int? ttl,
    String? text,
    String? senderName,
    String? device,
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
      via: via ?? this.via,
      receiverId: receiverId ?? this.receiverId,
      hop: hop ?? this.hop,
      ttl: ttl ?? this.ttl,
      text: text ?? this.text,
      senderName: senderName ?? this.senderName,
      device: device ?? this.device,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      status: status ?? this.status,
    );
  }
}
