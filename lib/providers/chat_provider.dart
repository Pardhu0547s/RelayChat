import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/bluetooth_service.dart';
import '../utils/protocol.dart';

class ChatProvider extends ChangeNotifier {
  final BluetoothService _bluetoothService = BluetoothService();
  final List<ChatMessage> _messages = [];
  final Map<String, DiscoveredUser> _discoveredUsers = {};
  
  final Map<String, List<Uint8List>> _voiceBuffers = {};
  final Map<String, List<Uint8List>> _imageBuffers = {};
  
  StreamSubscription<Frame>? _incomingSubscription;
  Timer? _helloTimer;
  
  final Uuid _uuid = const Uuid();
  late Uint8List _localPhoneIdBytes;
  late String localPhoneId;
  String localName = "User"; // Default, loaded from prefs

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<DiscoveredUser> get discoveredUsers => _discoveredUsers.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  Future<void>? _initFuture;

  ChatProvider() {
    _initFuture = _initIdentity();
  }

  Future<void> _waitForInit() async {
    if (_initFuture != null) await _initFuture;
  }

  Future<void> _initIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('local_phone_id');
    if (savedId != null) {
      localPhoneId = savedId;
      _localPhoneIdBytes = Uint8List.fromList(Uuid.parse(savedId));
    } else {
      _localPhoneIdBytes = _uuid.v4obj().toBytes();
      localPhoneId = Uuid.unparse(_localPhoneIdBytes);
      await prefs.setString('local_phone_id', localPhoneId);
    }
    localName = prefs.getString('local_name') ?? "User ${localPhoneId.substring(0, 4)}";
    
    debugPrint('📱 My Phone ID: $localPhoneId');
    _listenToIncomingData();
    _startHelloBroadcast();
  }
  
  void _startHelloBroadcast() {
    _helloTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _broadcastHello();
    });
  }
  
  Future<void> _broadcastHello() async {
    await _waitForInit();
    if (_bluetoothService.connectedDevice == null) return;
    
    final msgIdBytes = _uuid.v4obj().toBytes();
    final frame = Frame(
      type: FrameType.hello,
      origin: _localPhoneIdBytes,
      via: _localPhoneIdBytes,
      receiver: Frame.getBroadcastUuid(),
      messageId: msgIdBytes,
      payload: Frame.utf8ToBytes(localName),
    );
    
    await _bluetoothService.sendFrame(frame);
  }

  void onDeviceConnected() {
    Future.delayed(const Duration(seconds: 2), () {
      _broadcastHello();
    });
  }

  Future<void> setLocalName(String name) async {
    await _waitForInit();
    localName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_name', name);
    notifyListeners();
    _broadcastHello();
  }

  void _updateUserStats(String originStr, String viaStr, int rssi, {String? name}) {
    final double distance = rssi == 0 ? 0.0 : math.pow(10, (14 - rssi) / 25).toDouble();
    
    if (_discoveredUsers.containsKey(originStr)) {
      _discoveredUsers[originStr] = _discoveredUsers[originStr]!.copyWith(
        name: name,
        device: viaStr,
        lastSeen: DateTime.now(),
        rssi: rssi,
        distance: distance,
      );
    } else {
      _discoveredUsers[originStr] = DiscoveredUser(
        phoneId: originStr,
        name: name ?? "User ${originStr.substring(0, 4)}",
        device: viaStr,
        lastSeen: DateTime.now(),
        rssi: rssi,
        distance: distance,
      );
    }
    notifyListeners();
  }

  void _listenToIncomingData() {
    _incomingSubscription = _bluetoothService.incomingFrames.listen((frame) {
      final originStr = Uuid.unparse(frame.origin);
      final viaStr = Uuid.unparse(frame.via);
      final receiverStr = Uuid.unparse(frame.receiver);
      final msgIdStr = Uuid.unparse(frame.messageId);

      // Ignore our own looped back broadcasts
      if (originStr == localPhoneId) return;

      switch (frame.type) {
        case FrameType.hello:
          final senderName = Frame.bytesToUtf8(frame.payload);
          _updateUserStats(originStr, viaStr, frame.rssi, name: senderName);
          break;

        case FrameType.text:
          _updateUserStats(originStr, viaStr, frame.rssi);
          final text = Frame.bytesToUtf8(frame.payload);
          final msg = ChatMessage(
            id: msgIdStr,
            timestamp: DateTime.now(),
            type: MessageType.text,
            origin: originStr,
            via: viaStr,
            receiverId: receiverStr,
            text: text,
            isOutgoing: false,
            status: MessageStatus.delivered,
          );
          if (!_messages.any((m) => m.id == msgIdStr)) {
            _messages.add(msg);
            notifyListeners();
            _sendAck(frame.messageId, frame.origin);
          }
          break;

        case FrameType.ack:
          _updateUserStats(originStr, viaStr, frame.rssi);
          if (frame.payload.length == 16) {
            final ackFor = Uuid.unparse(frame.payload);
            final index = _messages.indexWhere((m) => m.id == ackFor);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(status: MessageStatus.delivered);
              notifyListeners();
            }
          }
          break;

        case FrameType.voice:
          _updateUserStats(originStr, viaStr, frame.rssi);
          _handleIncomingVoice(frame, originStr, viaStr, receiverStr, msgIdStr);
          break;
          
        case FrameType.location:
          _updateUserStats(originStr, viaStr, frame.rssi);
          final locationMessage = ChatMessage(
            id: msgIdStr,
            timestamp: DateTime.now(),
            type: MessageType.location,
            origin: originStr,
            via: viaStr,
            receiverId: receiverStr,
            text: Frame.bytesToUtf8(frame.payload),
            isOutgoing: false,
            status: MessageStatus.delivered,
          );
          if (!_messages.any((m) => m.id == msgIdStr)) {
            _messages.add(locationMessage);
            notifyListeners();
            _sendAck(frame.messageId, frame.origin);
          }
          break;

        case FrameType.image:
          _updateUserStats(originStr, viaStr, frame.rssi);
          _handleIncomingImage(frame, originStr, viaStr, receiverStr, msgIdStr);
          break;

        case FrameType.unknown:
          break;
      }
    });
  }

  Future<void> _handleIncomingVoice(Frame frame, String originStr, String viaStr, String receiverStr, String msgIdStr) async {
    if (frame.payload.length < 20) return;
    final buffer = ByteData.sublistView(frame.payload);
    final chunkIdx = buffer.getUint16(0, Endian.little);
    final totalChunks = buffer.getUint16(2, Endian.little);
    final voiceIdBytes = frame.payload.sublist(4, 20);
    final audioData = frame.payload.sublist(20);
    
    final voiceIdStr = Uuid.unparse(voiceIdBytes);

    if (!_voiceBuffers.containsKey(voiceIdStr)) {
      _voiceBuffers[voiceIdStr] = List.filled(totalChunks, Uint8List(0));
    }

    final bufferList = _voiceBuffers[voiceIdStr]!;
    if (chunkIdx < totalChunks) {
      bufferList[chunkIdx] = audioData;
    }

    if (!bufferList.any((chunk) => chunk.isEmpty)) {
      final fullAudio = BytesBuilder();
      for (final chunk in bufferList) fullAudio.add(chunk);
      
      _voiceBuffers.remove(voiceIdStr);
      
      final dir = await getTemporaryDirectory();
      final file = File('\${dir.path}/$voiceIdStr.m4a');
      await file.writeAsBytes(fullAudio.toBytes());

      final incomingMessage = ChatMessage(
        id: voiceIdStr,
        timestamp: DateTime.now(),
        type: MessageType.voice,
        origin: originStr,
        via: viaStr,
        receiverId: receiverStr,
        text: file.path,
        isOutgoing: false,
        status: MessageStatus.delivered,
      );

      if (!_messages.any((m) => m.id == voiceIdStr)) {
        _messages.add(incomingMessage);
        notifyListeners();
        _sendAck(voiceIdBytes, frame.origin); // ACK the parent voice ID
      }
    }
  }

  Future<void> _handleIncomingImage(Frame frame, String originStr, String viaStr, String receiverStr, String msgIdStr) async {
    if (frame.payload.length < 20) return;
    final buffer = ByteData.sublistView(frame.payload);
    final chunkIdx = buffer.getUint16(0, Endian.little);
    final totalChunks = buffer.getUint16(2, Endian.little);
    final imageIdBytes = frame.payload.sublist(4, 20);
    final imageData = frame.payload.sublist(20);
    
    final imageIdStr = Uuid.unparse(imageIdBytes);

    if (!_imageBuffers.containsKey(imageIdStr)) {
      _imageBuffers[imageIdStr] = List.filled(totalChunks, Uint8List(0));
    }

    final bufferList = _imageBuffers[imageIdStr]!;
    if (chunkIdx < totalChunks) {
      bufferList[chunkIdx] = imageData;
    }

    if (!bufferList.any((chunk) => chunk.isEmpty)) {
      final fullImage = BytesBuilder();
      for (final chunk in bufferList) fullImage.add(chunk);
      
      _imageBuffers.remove(imageIdStr);
      
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$imageIdStr.jpg');
      await file.writeAsBytes(fullImage.toBytes());

      final incomingMessage = ChatMessage(
        id: imageIdStr,
        timestamp: DateTime.now(),
        type: MessageType.image,
        origin: originStr,
        via: viaStr,
        receiverId: receiverStr,
        text: file.path,
        isOutgoing: false,
        status: MessageStatus.delivered,
      );

      if (!_messages.any((m) => m.id == imageIdStr)) {
        _messages.add(incomingMessage);
        notifyListeners();
        _sendAck(imageIdBytes, frame.origin); // ACK the parent image ID
      }
    }
  }

  Future<void> _sendAck(Uint8List originalMsgIdBytes, Uint8List receiverBytes) async {
    await _waitForInit();
    final ackMsgId = _uuid.v4obj().toBytes();
    final frame = Frame(
      type: FrameType.ack,
      origin: _localPhoneIdBytes,
      via: _localPhoneIdBytes,
      receiver: receiverBytes,
      messageId: ackMsgId,
      payload: originalMsgIdBytes, // The ID we are ACKing
    );
    await _bluetoothService.sendFrame(frame);
  }

  Future<void> sendMessage(String text, String receiverId, {bool isSos = false}) async {
    await _waitForInit();
    if (text.trim().isEmpty && !isSos) return;

    final msgIdBytes = _uuid.v4obj().toBytes();
    final msgIdStr = Uuid.unparse(msgIdBytes);
    final receiverBytes = Uint8List.fromList(Uuid.parse(receiverId));

    final outgoingMessage = ChatMessage(
      id: msgIdStr,
      timestamp: DateTime.now(),
      type: isSos ? MessageType.sos : MessageType.text,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: receiverId,
      text: isSos ? "SOS!" : text.trim(),
      isOutgoing: true,
      status: MessageStatus.sending, // Initial state
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    final frame = Frame(
      type: FrameType.text,
      origin: _localPhoneIdBytes,
      via: _localPhoneIdBytes,
      receiver: receiverBytes,
      messageId: msgIdBytes,
      payload: Frame.utf8ToBytes(isSos ? "SOS!" : text.trim()),
    );
    
    final success = await _bluetoothService.sendFrame(frame);
    
    final index = _messages.indexWhere((m) => m.id == msgIdStr);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        status: success ? MessageStatus.sent : MessageStatus.failed
      );
      notifyListeners();
    }
  }

  Future<void> sendVoiceBytes(Uint8List audioBytes, String receiverId) async {
    final msgIdBytes = _uuid.v4obj().toBytes();
    final msgIdStr = Uuid.unparse(msgIdBytes);
    final receiverBytes = Uint8List.fromList(Uuid.parse(receiverId));

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$msgIdStr.m4a');
    await file.writeAsBytes(audioBytes);

    final outgoingMessage = ChatMessage(
      id: msgIdStr,
      timestamp: DateTime.now(),
      type: MessageType.voice,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: receiverId,
      text: file.path,
      isOutgoing: true,
      status: MessageStatus.sending,
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    // Max frame payload is 1024, but LoRa limits to ~180. 
    // We leave room for 4 bytes of chunk header inside the payload.
    const maxChunkAudioSize = 140; 
    final totalChunks = (audioBytes.length / maxChunkAudioSize).ceil();

    bool allSent = true;
    for (int i = 0; i < totalChunks; i++) {
      final end = math.min(audioBytes.length, (i + 1) * maxChunkAudioSize);
      final chunkData = audioBytes.sublist(i * maxChunkAudioSize, end);
      
      final payload = BytesBuilder();
      final header = ByteData(4);
      header.setUint16(0, i, Endian.little);
      header.setUint16(2, totalChunks, Endian.little);
      payload.add(header.buffer.asUint8List());
      payload.add(chunkData);

      // Use a new messageId for each chunk to pass deduplication on the ESP32!
      // But how does receiver know they belong to the same voice message?
      // Wait, deduplication is based on MessageId!
      // If we use a different MessageId, how does the receiver group them?
      // We should use the same msgId for grouping, BUT add chunkIdx to it, or put msgId in payload?
      // Actually, since Voice frames are just chunks, we can put the parent VoiceId in the payload!
      // Let's modify Voice payload to: ChunkIdx(2), TotalChunks(2), ParentVoiceId(16), AudioData
      // and give each chunk frame a UNIQUE messageId for deduplication.
      
      // We'll update the payload format to include ParentVoiceId.
      final chunkPayload = BytesBuilder();
      chunkPayload.add(header.buffer.asUint8List());
      chunkPayload.add(msgIdBytes);
      chunkPayload.add(chunkData);

      final chunkFrameMsgId = _uuid.v4obj().toBytes(); // Unique ID for ESP32 routing deduplication

      final frame = Frame(
        type: FrameType.voice,
        origin: _localPhoneIdBytes,
        via: _localPhoneIdBytes,
        receiver: receiverBytes,
        messageId: chunkFrameMsgId,
        payload: chunkPayload.toBytes(),
      );

      final success = await _bluetoothService.sendFrame(frame);
      if (!success) allSent = false;
      await Future.delayed(const Duration(milliseconds: 600)); 
    }
    
    final index = _messages.indexWhere((m) => m.id == msgIdStr);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        status: allSent ? MessageStatus.sent : MessageStatus.failed
      );
      notifyListeners();
    }
  }

  Future<void> sendLocation(String latLng, String receiverId) async {
    await _waitForInit();
    final msgIdBytes = _uuid.v4obj().toBytes();
    final msgIdStr = Uuid.unparse(msgIdBytes);
    final receiverBytes = Uint8List.fromList(Uuid.parse(receiverId));

    final outgoingMessage = ChatMessage(
      id: msgIdStr,
      timestamp: DateTime.now(),
      type: MessageType.location,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: receiverId,
      text: latLng,
      isOutgoing: true,
      status: MessageStatus.sending,
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    final frame = Frame(
      type: FrameType.location,
      origin: _localPhoneIdBytes,
      via: _localPhoneIdBytes,
      receiver: receiverBytes,
      messageId: msgIdBytes,
      payload: Frame.utf8ToBytes(latLng),
    );
    
    final success = await _bluetoothService.sendFrame(frame);
    
    final index = _messages.indexWhere((m) => m.id == msgIdStr);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        status: success ? MessageStatus.sent : MessageStatus.failed
      );
      notifyListeners();
    }
  }

  Future<void> sendImageBytes(Uint8List imageBytes, String receiverId) async {
    final msgIdBytes = _uuid.v4obj().toBytes();
    final msgIdStr = Uuid.unparse(msgIdBytes);
    final receiverBytes = Uint8List.fromList(Uuid.parse(receiverId));

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$msgIdStr.jpg');
    await file.writeAsBytes(imageBytes);

    final outgoingMessage = ChatMessage(
      id: msgIdStr,
      timestamp: DateTime.now(),
      type: MessageType.image,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: receiverId,
      text: file.path,
      isOutgoing: true,
      status: MessageStatus.sending,
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    const maxChunkImageSize = 140; 
    final totalChunks = (imageBytes.length / maxChunkImageSize).ceil();

    bool allSent = true;
    for (int i = 0; i < totalChunks; i++) {
      final end = math.min(imageBytes.length, (i + 1) * maxChunkImageSize);
      final chunkData = imageBytes.sublist(i * maxChunkImageSize, end);
      
      final payload = BytesBuilder();
      final header = ByteData(4);
      header.setUint16(0, i, Endian.little);
      header.setUint16(2, totalChunks, Endian.little);
      payload.add(header.buffer.asUint8List());
      payload.add(msgIdBytes);
      payload.add(chunkData);

      final chunkFrameMsgId = _uuid.v4obj().toBytes();

      final frame = Frame(
        type: FrameType.image,
        origin: _localPhoneIdBytes,
        via: _localPhoneIdBytes,
        receiver: receiverBytes,
        messageId: chunkFrameMsgId,
        payload: payload.toBytes(),
      );

      final success = await _bluetoothService.sendFrame(frame);
      if (!success) allSent = false;
      await Future.delayed(const Duration(milliseconds: 600)); 
    }
    
    final index = _messages.indexWhere((m) => m.id == msgIdStr);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        status: allSent ? MessageStatus.sent : MessageStatus.failed
      );
      notifyListeners();
    }
  }

  List<ChatMessage> getMessagesForUser(String userId) {
      return _messages.where((m) => m.receiverId == userId || m.origin == userId || m.receiverId == Uuid.unparse(Frame.getBroadcastUuid())).toList();
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
