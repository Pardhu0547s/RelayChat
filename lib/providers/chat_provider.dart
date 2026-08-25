import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../services/bluetooth_service.dart';

class ChatProvider extends ChangeNotifier {
  final BluetoothService _bluetoothService = BluetoothService();
  final List<ChatMessage> _messages = [];
  StreamSubscription<String>? _incomingSubscription;
  final String _localPhoneId = "PHONE_001"; // In future, generate or load from prefs

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  ChatProvider() {
    _listenToIncomingMessages();
  }

  void _listenToIncomingMessages() {
    _incomingSubscription = _bluetoothService.incomingMessages.listen((incomingText) {
      try {
        final parsedMessage = ChatMessage.fromJson(incomingText, isOutgoing: false);
        
        if (parsedMessage.type == MessageType.ack) {
          // Handle ACK by marking the message as delivered
          final index = _messages.indexWhere((m) => m.id == parsedMessage.id);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(status: MessageStatus.delivered);
            notifyListeners();
          }
        } else if (parsedMessage.type == MessageType.text) {
          // Add as a new incoming message
          _messages.add(parsedMessage);
          notifyListeners();
        }
        // Handle other types later (status, etc.)
      } catch (e) {
        debugPrint('Failed to parse incoming message as JSON: $incomingText');
      }
    });
  }

  Future<void> sendMessage(String text, {bool isSos = false}) async {
    if (text.trim().isEmpty && !isSos) return;

    // In Phase 1.5, we use logical Node IDs instead of MAC addresses. 
    // Since we don't store the exact ESP32 Node ID prior to connecting yet, 
    // we use BROADCAST, and the connected node will respond with its actual ID.
    final receiverId = "BROADCAST";
    
    final outgoingMessage = ChatMessage(
      id: "msg_${DateTime.now().millisecondsSinceEpoch}",
      timestamp: DateTime.now(),
      type: isSos ? MessageType.sos : MessageType.text,
      origin: _localPhoneId,
      lastRelay: _localPhoneId,
      receiverId: receiverId,
      text: isSos ? "SOS!" : text.trim(),
      isOutgoing: true,
      status: MessageStatus.sent, // Start as sent, updated to delivered when ACK received
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    // Convert to JSON and send over BLE with newline framing
    final jsonPayload = '${outgoingMessage.toJson()}\n';
    await _bluetoothService.sendMessage(jsonPayload);
  }

  void clearChat() {
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    super.dispose();
  }
}
