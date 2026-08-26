import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/bluetooth_service.dart';

class ChatProvider extends ChangeNotifier {
  final BluetoothService _bluetoothService = BluetoothService();
  final List<ChatMessage> _messages = [];
  final Map<String, DiscoveredUser> _discoveredUsers = {};
  
  StreamSubscription<String>? _incomingSubscription;
  Timer? _helloTimer;
  
  final String localPhoneId = "PHONE_001";
  final String localName = "Pavan";

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<DiscoveredUser> get discoveredUsers => _discoveredUsers.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  ChatProvider() {
    _listenToIncomingMessages();
    _startHelloBroadcast();
  }
  
  void _startHelloBroadcast() {
     _helloTimer = Timer.periodic(const Duration(seconds: 20), (_) {
         _broadcastHello();
     });
     // broadcast immediately as well
     Future.delayed(const Duration(seconds: 1), _broadcastHello);
  }
  
  Future<void> _broadcastHello() async {
    final helloMsg = ChatMessage(
      id: "hello_${DateTime.now().millisecondsSinceEpoch}",
      timestamp: DateTime.now(),
      type: MessageType.hello,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: "BROADCAST",
      senderName: localName,
      text: "",
      isOutgoing: true,
      status: MessageStatus.sent,
    );
    final jsonPayload = '${helloMsg.toJson()}\n';
    await _bluetoothService.sendMessage(jsonPayload);
  }

  void _listenToIncomingMessages() {
    _incomingSubscription = _bluetoothService.incomingMessages.listen((incomingText) {
      try {
        final parsedMessage = ChatMessage.fromJson(incomingText, isOutgoing: false);
        
        if (parsedMessage.type == MessageType.hello) {
            // Update discovered users
            final user = DiscoveredUser(
              phoneId: parsedMessage.origin,
              name: parsedMessage.senderName ?? "Unknown",
              device: parsedMessage.via, // Use via (the ESP32 relay node) as device for now
              lastSeen: parsedMessage.timestamp,
            );
            _discoveredUsers[parsedMessage.origin] = user;
            notifyListeners();
        } else if (parsedMessage.type == MessageType.ack) {
          // Handle ACK by marking the message as delivered
          final index = _messages.indexWhere((m) => m.id == parsedMessage.id);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(status: MessageStatus.delivered);
            notifyListeners();
          }
        } else if (parsedMessage.type == MessageType.text || parsedMessage.type == MessageType.sos) {
          // Add as a new incoming message
          // Filter duplicates if any (ESP32 should handle, but just in case)
          if (!_messages.any((m) => m.id == parsedMessage.id)) {
            _messages.add(parsedMessage);
            notifyListeners();
            
            // Generate E2E ACK back to the origin
            _sendAck(parsedMessage.id, parsedMessage.origin);
          }
        }
      } catch (e) {
        debugPrint('Failed to parse incoming message as JSON: $incomingText');
      }
    });
  }

  Future<void> _sendAck(String originalMsgId, String receiverId) async {
      final ackMsg = ChatMessage(
          id: originalMsgId, // Use original ID so the sender can match it
          timestamp: DateTime.now(),
          type: MessageType.ack,
          origin: localPhoneId,
          via: localPhoneId,
          receiverId: receiverId, // Route it back to the original sender
          text: "received", // status
          isOutgoing: true,
          status: MessageStatus.sent,
      );
      final jsonPayload = '${ackMsg.toJson()}\n';
      await _bluetoothService.sendMessage(jsonPayload);
  }

  Future<void> sendMessage(String text, String receiverId, {bool isSos = false}) async {
    if (text.trim().isEmpty && !isSos) return;

    final outgoingMessage = ChatMessage(
      id: "msg_${DateTime.now().millisecondsSinceEpoch}",
      timestamp: DateTime.now(),
      type: isSos ? MessageType.sos : MessageType.text,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: receiverId,
      text: isSos ? "SOS!" : text.trim(),
      isOutgoing: true,
      status: MessageStatus.sent,
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    final jsonPayload = '${outgoingMessage.toJson()}\n';
    await _bluetoothService.sendMessage(jsonPayload);
  }

  List<ChatMessage> getMessagesForUser(String userId) {
      return _messages.where((m) => m.receiverId == userId || m.origin == userId || m.receiverId == "BROADCAST").toList();
  }

  void clearChat() {
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    _helloTimer?.cancel();
    super.dispose();
  }
}
