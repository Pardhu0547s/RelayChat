import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../services/bluetooth_service.dart';

class ChatProvider extends ChangeNotifier {
  final BluetoothService _bluetoothService = BluetoothService();
  final List<ChatMessage> _messages = [];
  StreamSubscription<String>? _incomingSubscription;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  ChatProvider() {
    _listenToIncomingMessages();
  }

  void _listenToIncomingMessages() {
    _incomingSubscription = _bluetoothService.incomingMessages.listen((incomingText) {
      final newMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: _bluetoothService.connectedDevice?.name ?? 'ESP32',
        senderName: _bluetoothService.connectedDevice?.name ?? 'ESP32',
        text: incomingText,
        timestamp: DateTime.now(),
        isOutgoing: false,
        status: MessageStatus.delivered,
      );
      _messages.add(newMessage);
      notifyListeners();
    });
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final outgoingMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: 'User',
      senderName: 'You',
      text: text.trim(),
      timestamp: DateTime.now(),
      isOutgoing: true,
      status: MessageStatus.sent,
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    await _bluetoothService.sendMessage(text.trim());
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
