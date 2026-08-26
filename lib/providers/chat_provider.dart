import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/bluetooth_service.dart';
import '../utils/protocol.dart';

class ChatProvider extends ChangeNotifier {
  final BluetoothService _bluetoothService = BluetoothService();
  final List<ChatMessage> _messages = [];
  final Map<String, DiscoveredUser> _discoveredUsers = {};
  
  // Voice chunk buffers
  final Map<String, List<Uint8List>> _voiceBuffers = {};
  
  StreamSubscription<Uint8List>? _incomingSubscription;
  StreamSubscription<double>? _connectionSubscription;
  Timer? _helloTimer;
  
  late final String localPhoneId;
  final String localName = "Pavan";

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<DiscoveredUser> get discoveredUsers => _discoveredUsers.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  ChatProvider() {
    localPhoneId = "PHONE_${const Uuid().v4().substring(0, 6).toUpperCase()}";
    _listenToIncomingData();
    _startHelloBroadcast();
  }
  
  void _startHelloBroadcast() {
     _connectionSubscription = _bluetoothService.connectionProgress.listen((progress) {
       if (progress == 1.0) {
         // Connected!
         Future.delayed(const Duration(seconds: 2), _broadcastHello);
       }
     });

     _helloTimer = Timer.periodic(const Duration(seconds: 20), (_) {
         if (_bluetoothService.connectedDevice != null) {
           _broadcastHello();
         }
     });
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
    await _bluetoothService.sendMessage(jsonPayload); // Fallback to send string
  }

  String _jsonBuffer = "";

  void _listenToIncomingData() {
    _incomingSubscription = _bluetoothService.incomingData.listen((bytes) {
      if (bytes.isEmpty) return;
      
      if (bytes[0] == BinaryProtocol.MAGIC_BYTE) {
        _handleIncomingBinary(bytes);
      } else {
        _handleIncomingJsonChunk(bytes);
      }
    });
  }

  void _handleIncomingJsonChunk(Uint8List bytes) {
    try {
      _jsonBuffer += utf8.decode(bytes);
      while (true) {
        final newlineIdx = _jsonBuffer.indexOf('\n');
        if (newlineIdx == -1) break;
        
        final packet = _jsonBuffer.substring(0, newlineIdx);
        _jsonBuffer = _jsonBuffer.substring(newlineIdx + 1);
        
        if (packet.trim().isNotEmpty) {
          _parseJsonPacket(packet);
        }
      }
    } catch (e) {
      debugPrint('Error decoding JSON chunk: $e');
    }
  }

  void _parseJsonPacket(String incomingText) {
    try {
      final parsedMessage = ChatMessage.fromJson(incomingText, isOutgoing: false);
      
      if (parsedMessage.type == MessageType.hello) {
          final user = DiscoveredUser(
            phoneId: parsedMessage.origin,
            name: parsedMessage.senderName ?? "Unknown",
            device: parsedMessage.via,
            lastSeen: parsedMessage.timestamp,
          );
          _discoveredUsers[parsedMessage.origin] = user;
          notifyListeners();
      } else if (parsedMessage.type == MessageType.ack) {
        final index = _messages.indexWhere((m) => m.id == parsedMessage.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(status: MessageStatus.delivered);
          notifyListeners();
        }
      } else if (parsedMessage.type == MessageType.text || parsedMessage.type == MessageType.sos) {
        if (!_messages.any((m) => m.id == parsedMessage.id)) {
          _messages.add(parsedMessage);
          notifyListeners();
          _sendAck(parsedMessage.id, parsedMessage.origin);
        }
      }
    } catch (e) {
      debugPrint('Failed to parse incoming message as JSON: $incomingText');
    }
  }

  Future<void> _handleIncomingBinary(Uint8List bytes) async {
    final header = BinaryProtocol.decodeHeader(bytes);
    if (header == null) return;

    final voiceId = header['voiceId'] as String;
    final chunkIdx = header['chunkIdx'] as int;
    final totalChunks = header['totalChunks'] as int;
    final payload = header['payload'] as Uint8List;

    if (!_voiceBuffers.containsKey(voiceId)) {
      _voiceBuffers[voiceId] = List.filled(totalChunks, Uint8List(0));
    }

    final bufferList = _voiceBuffers[voiceId]!;
    if (chunkIdx < totalChunks) {
      bufferList[chunkIdx] = payload;
    }

    // Check if all chunks are received
    if (!bufferList.any((chunk) => chunk.isEmpty)) {
      final fullAudio = BytesBuilder();
      for (final chunk in bufferList) {
        fullAudio.add(chunk);
      }
      
      _voiceBuffers.remove(voiceId); // Cleanup
      
      // Save to temporary file
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$voiceId.m4a');
      await file.writeAsBytes(fullAudio.toBytes());

      final incomingMessage = ChatMessage(
        id: voiceId,
        timestamp: DateTime.now(),
        type: MessageType.voice,
        origin: header['origin'],
        via: header['via'],
        receiverId: header['receiver'],
        text: file.path, // Store the local file path here
        isOutgoing: false,
        status: MessageStatus.delivered,
      );

      if (!_messages.any((m) => m.id == voiceId)) {
        _messages.add(incomingMessage);
        notifyListeners();
        _sendAck(voiceId, header['origin']);
      }
    }
  }

  Future<void> _sendAck(String originalMsgId, String receiverId) async {
      final ackMsg = ChatMessage(
          id: originalMsgId,
          timestamp: DateTime.now(),
          type: MessageType.ack,
          origin: localPhoneId,
          via: localPhoneId,
          receiverId: receiverId,
          text: "received",
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

  Future<void> sendVoiceBytes(Uint8List audioBytes, String receiverId) async {
    final voiceId = "voice_${DateTime.now().millisecondsSinceEpoch}";
    final chunkSize = 180;
    final totalChunks = (audioBytes.length / chunkSize).ceil();

    // Add to UI immediately
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$voiceId.m4a');
    await file.writeAsBytes(audioBytes);

    final outgoingMessage = ChatMessage(
      id: voiceId,
      timestamp: DateTime.now(),
      type: MessageType.voice,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: receiverId,
      text: file.path,
      isOutgoing: true,
      status: MessageStatus.sending, // will update to sent later or loop
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    // Send chunks
    for (int i = 0; i < totalChunks; i++) {
      final end = math.min(audioBytes.length, (i + 1) * chunkSize);
      final chunk = audioBytes.sublist(i * chunkSize, end);
      
      final packet = BinaryProtocol.encodeVoiceChunk(
        ttl: 8,
        hop: 0,
        origin: localPhoneId,
        receiver: receiverId,
        via: localPhoneId,
        voiceId: voiceId,
        chunkIdx: i,
        totalChunks: totalChunks,
        payload: chunk,
      );

      await _bluetoothService.sendBytes(packet);
      // Pacing for LoRa throughput (e.g. max ~1-2 packets per second depending on SF)
      // Since it's MVP, we just add a delay. 
      await Future.delayed(const Duration(milliseconds: 200)); 
    }
    
    // Update status to sent locally
    final index = _messages.indexWhere((m) => m.id == voiceId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(status: MessageStatus.sent);
      notifyListeners();
    }
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
    _connectionSubscription?.cancel();
    _helloTimer?.cancel();
    super.dispose();
  }
}
