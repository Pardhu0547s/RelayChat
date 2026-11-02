import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/bluetooth_device.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/bluetooth_service.dart';
import '../utils/color_image_codec.dart';
import '../utils/color_paper_codec.dart';
import '../utils/paper_codec.dart';
import '../utils/protocol.dart';
import '../utils/transfer_config.dart';

/// Reassembly state for an image that is currently arriving over LoRa.
class _IncomingImage {
  final Uint8List idBytes;
  final Uint8List senderBytes; // who we NACK / ACK
  final String originStr;
  final String viaStr;
  final String receiverStr;
  final List<Uint8List?> chunks;
  int nackCount = 0;
  Timer? timer;

  _IncomingImage({
    required this.idBytes,
    required this.senderBytes,
    required this.originStr,
    required this.viaStr,
    required this.receiverStr,
    required int total,
  }) : chunks = List<Uint8List?>.filled(total, null);

  int get total => chunks.length;
  int get receivedCount => chunks.where((c) => c != null).length;
  bool get isComplete => receivedCount == total;
}

/// Chunk payloads we keep after sending so we can answer NACKs.
class _OutgoingImage {
  final List<Uint8List> payloads;
  final Uint8List receiverBytes;
  Timer? expiry;
  bool busy = false; // true while (re)transmitting, to avoid overlapping bursts

  _OutgoingImage({required this.payloads, required this.receiverBytes});
}

class ChatProvider extends ChangeNotifier {
  // ---- Image reliability tuning ----
  static const int _maxChunkData = TransferConfig.chunkDataBytes; // data bytes per LoRa packet
  static const int _maxImageChunks = TransferConfig.maxChunks; // sanity bound against corrupt headers
  // How long the receiver waits before asking for missing chunks:
  //  - _tailWait: after the LAST chunk arrived (the sender is done, only stragglers remain)
  //  - _nackSilence: when the stream just goes quiet (last chunk lost / mid-burst gap).
  // Chunks are ~0.5 s apart, so 3.5 s of silence is already ~7 missed slots.
  static const Duration _tailWait = Duration(milliseconds: 1500);
  static const Duration _nackSilence = Duration(milliseconds: 3500);
  static const int _maxNackRetries = 3;
  static const Duration _outgoingTtl = Duration(minutes: 2);
  static const Duration _chunkPacing = TransferConfig.chunkPacing;

  final BluetoothService _bluetoothService = BluetoothService();
  final List<ChatMessage> _messages = [];
  final Map<String, DiscoveredUser> _discoveredUsers = {};

  // ---- SOS alarm: plays on the device that RECEIVES an SOS, never on the sender ----
  static const String _sosSound = 'Sounds/soundreality-sos-signal-137144.mp3';
  static const Duration _sosAutoStop = Duration(minutes: 2);
  final AudioPlayer _sosPlayer = AudioPlayer();
  Timer? _sosTimer;
  bool _sosAlarmActive = false;
  String _sosFromName = 'a nearby device';
  bool get sosAlarmActive => _sosAlarmActive;
  String get sosFromName => _sosFromName;
  
  final Map<String, List<Uint8List>> _voiceBuffers = {};
  final Map<String, _IncomingImage> _incomingImages = {};
  final Map<String, _OutgoingImage> _outgoingImages = {};
  final Set<String> _completedImages = {};
  
  StreamSubscription<Frame>? _incomingSubscription;
  StreamSubscription<RelayDevice>? _deviceConnectedSub;
  Timer? _helloTimer;
  Timer? _saveUsersDebounce;
  DateTime? _lastHelloBroadcast;
  final Map<String, DateTime> _lastHelloReplySent = {};
  static const String _usersCacheKey = 'discovered_users_cache';
  
  final Uuid _uuid = const Uuid();
  late Uint8List _localPhoneIdBytes;
  late String localPhoneId;
  String localName = "User"; // Default, loaded from prefs

  /// Empty / 'BROADCAST' (the Broadcast Channel has no target user) -> all-zero UUID.
  String _normalizeReceiver(String id) =>
      (id.isEmpty || id == 'BROADCAST') ? Uuid.unparse(Frame.getBroadcastUuid()) : id;

  Uint8List _receiverBytes(String id) {
    try {
      return Uint8List.fromList(Uuid.parse(_normalizeReceiver(id)));
    } catch (_) {
      return Frame.getBroadcastUuid();
    }
  }

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
    await _loadDiscoveredUsers();
    _listenToIncomingData();
    _deviceConnectedSub = _bluetoothService.deviceConnected.listen((device) {
      debugPrint('📱 Device connected: ${device.name}, triggering discovery burst');
      onDeviceConnected();
    });
    _startHelloBroadcast();
  }

  Future<void> _loadDiscoveredUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_usersCacheKey);
      if (jsonList != null) {
        for (final item in jsonList) {
          final map = jsonDecode(item) as Map<String, dynamic>;
          final user = DiscoveredUser.fromJson(map);
          _discoveredUsers[user.phoneId] = user;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading cached users: $e');
    }
  }

  void _saveDiscoveredUsersDebounced() {
    _saveUsersDebounce?.cancel();
    _saveUsersDebounce = Timer(const Duration(seconds: 2), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = _discoveredUsers.values.map((u) => jsonEncode(u.toJson())).toList();
        await prefs.setStringList(_usersCacheKey, list);
      } catch (e) {
        debugPrint('Error saving discovered users: $e');
      }
    });
  }
  
  void _startHelloBroadcast() {
    _helloTimer?.cancel();
    _helloTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _broadcastHello();
    });
  }

  Future<void> broadcastHello() => _broadcastHello();
  
  Future<void> _broadcastHello() async {
    await _waitForInit();
    if (_bluetoothService.connectedDevice == null) return;
    _lastHelloBroadcast = DateTime.now();
    
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
    // 3-stage burst on connect ensures fast bidirectional discovery
    _broadcastHello();
    Future.delayed(const Duration(seconds: 2), () {
      _broadcastHello();
    });
    Future.delayed(const Duration(seconds: 5), () {
      _broadcastHello();
    });
    _startHelloBroadcast();
  }

  void _respondToHello(String peerPhoneId) {
    final now = DateTime.now();
    // Don't reply if we broadcasted very recently (< 4s) to avoid LoRa congestion
    if (_lastHelloBroadcast != null && now.difference(_lastHelloBroadcast!) < const Duration(seconds: 4)) {
      return;
    }
    // Don't reply to the same peer more than once every 12 seconds
    final lastReply = _lastHelloReplySent[peerPhoneId];
    if (lastReply != null && now.difference(lastReply) < const Duration(seconds: 12)) {
      return;
    }
    _lastHelloReplySent[peerPhoneId] = now;
    // Jitter delay (200-500ms) prevents half-duplex LoRa collisions
    final jitter = 200 + math.Random().nextInt(300);
    Future.delayed(Duration(milliseconds: jitter), () {
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
    _saveDiscoveredUsersDebounced();
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
          _respondToHello(originStr);
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
            _clearOutgoingImage(ackFor); // full image confirmed, free the chunks
          }
          break;

        case FrameType.sos:
          _updateUserStats(originStr, viaStr, frame.rssi);
          if (!_messages.any((m) => m.id == msgIdStr)) {
            _messages.add(ChatMessage(
              id: msgIdStr,
              timestamp: DateTime.now(),
              type: MessageType.sos,
              origin: originStr,
              via: viaStr,
              receiverId: receiverStr,
              text: 'SOS!',
              isOutgoing: false,
              status: MessageStatus.delivered,
            ));
            notifyListeners();
            _sendAck(frame.messageId, frame.origin);
            _startSosAlarm(originStr);
          }
          break;

        case FrameType.nack:
          _updateUserStats(originStr, viaStr, frame.rssi);
          _handleIncomingNack(frame);
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
      final file = File('${dir.path}/$voiceIdStr.m4a');
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
    final imageIdBytes = Uint8List.fromList(frame.payload.sublist(4, 20));
    final imageData = Uint8List.fromList(frame.payload.sublist(20));
    final imageIdStr = Uuid.unparse(imageIdBytes);

    if (totalChunks == 0 || totalChunks > _maxImageChunks || chunkIdx >= totalChunks) return;
    if (_completedImages.contains(imageIdStr)) return; // late duplicate of a finished image

    var incoming = _incomingImages[imageIdStr];
    if (incoming == null) {
      incoming = _IncomingImage(
        idBytes: imageIdBytes,
        senderBytes: Uint8List.fromList(frame.origin),
        originStr: originStr,
        viaStr: viaStr,
        receiverStr: receiverStr,
        total: totalChunks,
      );
      _incomingImages[imageIdStr] = incoming;
    } else if (incoming.total != totalChunks) {
      return; // inconsistent header, ignore
    }

    if (incoming.chunks[chunkIdx] == null) {
      incoming.nackCount = 0; // real progress, so the retry budget starts over
    }
    incoming.chunks[chunkIdx] = imageData;

    if (incoming.isComplete) {
      await _finishIncomingImage(imageIdStr, incoming);
    } else {
      final isTail = chunkIdx == totalChunks - 1;
      _armNackTimer(imageIdStr, incoming, isTail ? _tailWait : _nackSilence);
    }
  }

  Future<void> _finishIncomingImage(String imageIdStr, _IncomingImage incoming) async {
    // Remove first so any duplicate chunk arriving during the file write is ignored.
    incoming.timer?.cancel();
    _incomingImages.remove(imageIdStr);
    _completedImages.add(imageIdStr);

    final assembled = BytesBuilder();
    for (final chunk in incoming.chunks) {
      assembled.add(chunk!);
    }
    final data = assembled.toBytes();
    if (_messages.any((m) => m.id == imageIdStr)) return;

    final file = await _saveForDisplay(imageIdStr, data); // photo -> .jpg, paper -> unfolded .png
    if (file == null) {
      _messages.add(ChatMessage(
        id: 'imgfail-$imageIdStr',
        timestamp: DateTime.now(),
        type: MessageType.system,
        origin: incoming.originStr,
        via: incoming.viaStr,
        receiverId: localPhoneId,
        text: 'Received an image that could not be decoded.',
        isOutgoing: false,
        status: MessageStatus.failed,
      ));
      notifyListeners();
      return;
    }

    _messages.add(ChatMessage(
      id: imageIdStr,
      timestamp: DateTime.now(),
      type: MessageType.image,
      origin: incoming.originStr,
      via: incoming.viaStr,
      receiverId: incoming.receiverStr,
      text: file.path,
      isOutgoing: false,
      status: MessageStatus.delivered,
    ));
    notifyListeners();
    _sendAck(incoming.idBytes, incoming.senderBytes); // ACK the parent image ID
  }

  /// Writes what we received (or sent) to a displayable image file.
  /// Paper blobs (B&W or color) are "unfolded" into a smooth 2x PNG; photos are stored as-is.
  Future<File?> _saveForDisplay(String idStr, Uint8List data) async {
    final dir = await getTemporaryDirectory();
    if (PaperCodec.isPaper(data)) {
      final bmp = PaperCodec.unpack(data);
      if (bmp == null) return null;
      final file = File('${dir.path}/$idStr.png');
      await file.writeAsBytes(await PaperCodec.toPng(bmp));
      return file;
    }
    if (ColorPaperCodec.isColorPaper(data)) {
      final bmp = ColorPaperCodec.unpack(data);
      if (bmp == null) return null;
      final file = File('${dir.path}/$idStr.png');
      await file.writeAsBytes(await ColorPaperCodec.toPng(bmp));
      return file;
    }
    if (ColorImageCodec.isColorImage(data)) {
      final bmp = ColorImageCodec.unpack(data);
      if (bmp == null) return null;
      final file = File('${dir.path}/$idStr.png');
      await file.writeAsBytes(await ColorImageCodec.toPng(bmp));
      return file;
    }
    final file = File('${dir.path}/$idStr.jpg');
    await file.writeAsBytes(data);
    return file;
  }

  // ---------- Selective retransmission: receiver side ----------

  void _armNackTimer(String imageIdStr, _IncomingImage incoming, [Duration wait = _nackSilence]) {
    incoming.timer?.cancel();
    incoming.timer = Timer(wait, () => _onImageSilence(imageIdStr));
  }

  void _onImageSilence(String imageIdStr) {
    final incoming = _incomingImages[imageIdStr];
    if (incoming == null) return;

    if (incoming.nackCount >= _maxNackRetries) {
      _incomingImages.remove(imageIdStr);
      _messages.add(ChatMessage(
        id: 'imgfail-$imageIdStr',
        timestamp: DateTime.now(),
        type: MessageType.system,
        origin: incoming.originStr,
        via: incoming.viaStr,
        receiverId: localPhoneId,
        text: 'Incoming image or scan failed to arrive (${incoming.receivedCount}/${incoming.total} parts received).',
        isOutgoing: false,
        status: MessageStatus.failed,
      ));
      notifyListeners();
      return;
    }

    incoming.nackCount++;
    _sendNack(incoming);
    _armNackTimer(imageIdStr, incoming); // wait again for the retransmission
  }

  /// NACK payload: imageId(16) + bitmap (bit i of byte i>>3 set = chunk i received).
  Future<void> _sendNack(_IncomingImage incoming) async {
    await _waitForInit();
    final bitmap = Uint8List((incoming.total + 7) ~/ 8);
    for (int i = 0; i < incoming.total; i++) {
      if (incoming.chunks[i] != null) bitmap[i >> 3] |= (1 << (i & 7));
    }
    final payload = BytesBuilder()
      ..add(incoming.idBytes)
      ..add(bitmap);

    final frame = Frame(
      type: FrameType.nack,
      origin: _localPhoneIdBytes,
      via: _localPhoneIdBytes,
      receiver: incoming.senderBytes,
      messageId: _uuid.v4obj().toBytes(), // fresh ID so the ESP32 dedup lets it through
      payload: payload.toBytes(),
    );
    await _bluetoothService.sendFrame(frame);
  }

  // ---------- Selective retransmission: sender side ----------

  void _clearOutgoingImage(String imageIdStr) {
    _outgoingImages.remove(imageIdStr)?.expiry?.cancel();
  }

  Future<void> _handleIncomingNack(Frame frame) async {
    if (frame.payload.length < 17) return;
    final imageIdStr = Uuid.unparse(frame.payload.sublist(0, 16));
    final outgoing = _outgoingImages[imageIdStr];
    if (outgoing == null || outgoing.busy) return;

    final bitmap = frame.payload.sublist(16);
    final missing = <int>[];
    for (int i = 0; i < outgoing.payloads.length; i++) {
      final byteIdx = i >> 3;
      final received = byteIdx < bitmap.length && (bitmap[byteIdx] & (1 << (i & 7))) != 0;
      if (!received) missing.add(i);
    }
    if (missing.isEmpty) return;

    debugPrint('🔁 NACK for $imageIdStr: resending ${missing.length}/${outgoing.payloads.length} chunks');
    outgoing.busy = true;
    outgoing.expiry?.cancel();
    try {
      for (final i in missing) {
        if (!_outgoingImages.containsKey(imageIdStr)) break; // ACKed or expired meanwhile
        await _sendImageChunk(outgoing.payloads[i], outgoing.receiverBytes);
        await Future.delayed(_chunkPacing);
      }
    } finally {
      outgoing.busy = false;
      if (_outgoingImages.containsKey(imageIdStr)) {
        outgoing.expiry = Timer(_outgoingTtl, () => _clearOutgoingImage(imageIdStr));
      }
    }
  }

  Future<bool> _sendImageChunk(Uint8List payload, Uint8List receiverBytes) {
    final frame = Frame(
      type: FrameType.image,
      origin: _localPhoneIdBytes,
      via: _localPhoneIdBytes,
      receiver: receiverBytes,
      messageId: _uuid.v4obj().toBytes(), // unique per (re)transmission for ESP32 dedup
      payload: payload,
    );
    return _bluetoothService.sendFrame(frame);
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

  Future<void> _startSosAlarm(String originStr) async {
    _sosFromName = _discoveredUsers[originStr]?.name ?? 'a nearby device';
    _sosAlarmActive = true;
    notifyListeners();

    _sosTimer?.cancel();
    _sosTimer = Timer(_sosAutoStop, stopSosAlarm); // never ring forever
    try {
      // Alarm audio stream: still audible in silent/vibrate mode on most phones.
      await _sosPlayer.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ));
      await _sosPlayer.setReleaseMode(ReleaseMode.loop);
      await _sosPlayer.setVolume(1.0);
      await _sosPlayer.play(AssetSource(_sosSound));
    } catch (e) {
      debugPrint('SOS alarm playback failed: $e');
    }
  }

  Future<void> stopSosAlarm() async {
    _sosTimer?.cancel();
    _sosTimer = null;
    try {
      await _sosPlayer.stop();
    } catch (_) {}
    if (_sosAlarmActive) {
      _sosAlarmActive = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text, String receiverId, {bool isSos = false}) async {
    await _waitForInit();
    if (text.trim().isEmpty && !isSos) return;

    final msgIdBytes = _uuid.v4obj().toBytes();
    final msgIdStr = Uuid.unparse(msgIdBytes);
    final receiverBytes = _receiverBytes(receiverId);

    final outgoingMessage = ChatMessage(
      id: msgIdStr,
      timestamp: DateTime.now(),
      type: isSos ? MessageType.sos : MessageType.text,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: _normalizeReceiver(receiverId),
      text: isSos ? "SOS!" : text.trim(),
      isOutgoing: true,
      status: MessageStatus.sending, // Initial state
    );

    _messages.add(outgoingMessage);
    notifyListeners();

    final frame = Frame(
      type: isSos ? FrameType.sos : FrameType.text,
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
    await _waitForInit();
    final msgIdBytes = _uuid.v4obj().toBytes();
    final msgIdStr = Uuid.unparse(msgIdBytes);
    final receiverBytes = _receiverBytes(receiverId);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$msgIdStr.m4a');
    await file.writeAsBytes(audioBytes);

    final outgoingMessage = ChatMessage(
      id: msgIdStr,
      timestamp: DateTime.now(),
      type: MessageType.voice,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: _normalizeReceiver(receiverId),
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
    final receiverBytes = _receiverBytes(receiverId);

    final outgoingMessage = ChatMessage(
      id: msgIdStr,
      timestamp: DateTime.now(),
      type: MessageType.location,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: _normalizeReceiver(receiverId),
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

  /// [imageBytes] is either a compressed photo (JPEG) or a paper blob from [PaperCodec].
  Future<void> sendImageBytes(Uint8List imageBytes, String receiverId) async {
    await _waitForInit();
    final msgIdBytes = _uuid.v4obj().toBytes();
    final msgIdStr = Uuid.unparse(msgIdBytes);

    final file = await _saveForDisplay(msgIdStr, imageBytes);
    if (file == null) return; // invalid paper blob, nothing to send
    _addOutgoing(msgIdStr, MessageType.image, receiverId, file.path);
    await _transmitBlob(msgIdStr, msgIdBytes, imageBytes, _receiverBytes(receiverId));
  }

  void _addOutgoing(String msgIdStr, MessageType type, String receiverId, String text) {
    _messages.add(ChatMessage(
      id: msgIdStr,
      timestamp: DateTime.now(),
      type: type,
      origin: localPhoneId,
      via: localPhoneId,
      receiverId: _normalizeReceiver(receiverId),
      text: text,
      isOutgoing: true,
      status: MessageStatus.sending,
    ));
    notifyListeners();
  }

  /// Splits [blob] into chunks, sends them, and keeps them for NACK-driven resends.
  Future<void> _transmitBlob(String msgIdStr, Uint8List msgIdBytes, Uint8List blob, Uint8List receiverBytes) async {
    void setStatus(MessageStatus status) {
      final index = _messages.indexWhere((m) => m.id == msgIdStr);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: status);
        notifyListeners();
      }
    }

    final totalChunks = (blob.length / _maxChunkData).ceil();
    if (totalChunks == 0 || totalChunks > _maxImageChunks) {
      setStatus(MessageStatus.failed); // too large for LoRa
      return;
    }

    // Build every chunk payload up front and keep them, so NACKs can be answered.
    final payloads = <Uint8List>[];
    for (int i = 0; i < totalChunks; i++) {
      final end = math.min(blob.length, (i + 1) * _maxChunkData);
      final header = ByteData(4)
        ..setUint16(0, i, Endian.little)
        ..setUint16(2, totalChunks, Endian.little);
      final payload = BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(msgIdBytes) // parent message ID, so the receiver can group chunks
        ..add(blob.sublist(i * _maxChunkData, end));
      payloads.add(payload.toBytes());
    }

    final outgoing = _OutgoingImage(payloads: payloads, receiverBytes: receiverBytes)..busy = true;
    _outgoingImages[msgIdStr] = outgoing;

    bool allSent = true;
    for (final payload in payloads) {
      final success = await _sendImageChunk(payload, receiverBytes);
      if (!success) allSent = false;
      await Future.delayed(_chunkPacing);
    }

    outgoing.busy = false;
    if (_outgoingImages.containsKey(msgIdStr)) {
      // Keep chunks for a while for NACK-driven resends (cleared early on ACK).
      outgoing.expiry = Timer(_outgoingTtl, () => _clearOutgoingImage(msgIdStr));
    }

    // Don't downgrade a message that was already ACKed (delivered) while sending.
    final index = _messages.indexWhere((m) => m.id == msgIdStr);
    if (index != -1 && _messages[index].status == MessageStatus.sending) {
      setStatus(allSent ? MessageStatus.sent : MessageStatus.failed);
    }
  }

  List<ChatMessage> getMessagesForUser(String userId) {
      final id = _normalizeReceiver(userId);
      return _messages.where((m) => m.receiverId == id || m.origin == id || m.receiverId == Uuid.unparse(Frame.getBroadcastUuid())).toList();
  }

  void clearChat() {
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    _deviceConnectedSub?.cancel();
    _helloTimer?.cancel();
    _saveUsersDebounce?.cancel();
    _sosTimer?.cancel();
    _sosPlayer.dispose();
    for (final incoming in _incomingImages.values) {
      incoming.timer?.cancel();
    }
    for (final outgoing in _outgoingImages.values) {
      outgoing.expiry?.cancel();
    }
    super.dispose();
  }
}
