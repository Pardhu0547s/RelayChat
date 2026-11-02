import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bluetooth_device.dart';
import '../utils/protocol.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  static const String _savedDeviceKey = 'last_esp32_mac';

  // Stream for parsed frames
  final StreamController<Frame> _incomingFrameController = StreamController<Frame>.broadcast();
  Stream<Frame> get incomingFrames => _incomingFrameController.stream;

  final StreamController<double> _connectionProgressController = StreamController<double>.broadcast();
  Stream<double> get connectionProgress => _connectionProgressController.stream;

  final StreamController<bool> _deviceDisconnectedController = StreamController<bool>.broadcast();
  Stream<bool> get deviceDisconnected => _deviceDisconnectedController.stream;

  final StreamController<RelayDevice> _deviceConnectedController = StreamController<RelayDevice>.broadcast();
  Stream<RelayDevice> get deviceConnected => _deviceConnectedController.stream;

  RelayDevice? _connectedDevice;
  RelayDevice? get connectedDevice => _connectedDevice;

  fbp.BluetoothCharacteristic? _txCharacteristic;
  fbp.BluetoothCharacteristic? _rxCharacteristic;

  // Frame reassembly buffer
  final BytesBuilder _rxBuffer = BytesBuilder();

  // Active BLE subscriptions. Cancelled on every (re)connect/disconnect so we never
  // end up with duplicate listeners feeding the same reassembly buffer.
  StreamSubscription<List<int>>? _rxSub;
  StreamSubscription<fbp.BluetoothConnectionState>? _connSub;

  Future<void> _cancelSubscriptions() async {
    await _rxSub?.cancel();
    await _connSub?.cancel();
    _rxSub = null;
    _connSub = null;
    _rxBuffer.clear();
  }

  // ──────────────────────────────────────────────────────────
  //  Saved Device (Auto-Reconnect)
  // ──────────────────────────────────────────────────────────

  Future<void> saveLastDevice(String macAddress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedDeviceKey, macAddress);
  }

  Future<String?> getLastDeviceMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedDeviceKey);
  }

  Future<void> clearSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedDeviceKey);
  }

  Future<bool> autoConnect() async {
    final mac = await getLastDeviceMac();
    if (mac == null || mac.isEmpty) return false;

    _connectionProgressController.add(0.1);
    try {
      await _cancelSubscriptions();
      final nativeDevice = fbp.BluetoothDevice.fromId(mac);
      _connectionProgressController.add(0.2);
      
      await nativeDevice.connect(license: fbp.License.nonprofit, timeout: const Duration(seconds: 10));

      if (Platform.isAndroid) {
        try {
          await nativeDevice.requestMtu(512);
        } catch (_) {}
      }

      _connSub = nativeDevice.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          if (_connectedDevice != null) {
            _connectedDevice = null;
            _txCharacteristic = null;
            _rxCharacteristic = null;
            _rxBuffer.clear();
            _rxSub?.cancel();
            _rxSub = null;
            _deviceDisconnectedController.add(true);
          }
        }
      });

      _connectionProgressController.add(0.5);
      final services = await nativeDevice.discoverServices();
      _connectionProgressController.add(0.7);

      for (var service in services) {
        if (service.uuid.toString().toUpperCase().contains('6E400001')) {
          for (var char in service.characteristics) {
            final charUuid = char.uuid.toString().toUpperCase();
            if (charUuid.contains('6E400002')) _txCharacteristic = char;
            if (charUuid.contains('6E400003')) _rxCharacteristic = char;
          }
        }
      }

      _connectionProgressController.add(0.9);

      if (_rxCharacteristic != null) {
        await _rxCharacteristic!.setNotifyValue(true);
        _rxSub = _rxCharacteristic!.onValueReceived.listen(_handleIncomingBleBytes);
      }

      _connectionProgressController.add(1.0);

      _connectedDevice = RelayDevice(
        id: mac,
        name: '📡 RelayChat ESP32',
        rssi: -50,
        isAvailable: true,
        nativeDevice: nativeDevice,
      );
      _deviceConnectedController.add(_connectedDevice!);

      return true;
    } catch (e) {
      _connectionProgressController.add(0.0);
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Permissions & Bluetooth Status
  // ──────────────────────────────────────────────────────────

  Future<bool> checkPermissions() async {
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) return true;
    if (Platform.isAndroid) {
      final scan = await Permission.bluetoothScan.status;
      final connect = await Permission.bluetoothConnect.status;
      final loc = await Permission.locationWhenInUse.status;
      if (scan.isGranted && connect.isGranted) return true;
      if (loc.isGranted) return true;
      return false;
    }
    if (Platform.isIOS) return await Permission.bluetooth.status.isGranted;
    return true;
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) return true;
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ].request();
      final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;
      if ((scanOk && connectOk) || locOk) return true;
      if (statuses.values.any((s) => s.isPermanentlyDenied)) {
        await openAppSettings();
        return await checkPermissions();
      }
      return false;
    }
    if (Platform.isIOS) {
      final status = await Permission.bluetooth.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return await checkPermissions();
      }
      return status.isGranted;
    }
    return true;
  }

  Future<bool> isBluetoothEnabled() async {
    if (kIsWeb || Platform.isLinux) return true;
    try {
      final state = await fbp.FlutterBluePlus.adapterState.first;
      return state == fbp.BluetoothAdapterState.on;
    } catch (_) {
      return true;
    }
  }

  Future<void> turnOnBluetooth() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await fbp.FlutterBluePlus.turnOn();
      } catch (_) {}
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Scan Devices
  // ──────────────────────────────────────────────────────────

  Future<List<RelayDevice>> scanDevices() async {
    final Map<String, RelayDevice> deviceMap = {};
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) return [];

    try {
      if (fbp.FlutterBluePlus.isScanningNow) await fbp.FlutterBluePlus.stopScan();

      StreamSubscription? scanSub;
      scanSub = fbp.FlutterBluePlus.onScanResults.listen((results) {
        for (var result in results) {
          final id = result.device.remoteId.str;
          final serviceUuids = result.advertisementData.serviceUuids.map((g) => g.toString().toUpperCase()).toList();
          
          if (!serviceUuids.contains('6E400001-B5A3-F393-E0A9-E50E24DCCA9E')) continue;

          if (!deviceMap.containsKey(id) || result.rssi > (deviceMap[id]?.rssi ?? -999)) {
            deviceMap[id] = RelayDevice(
              id: id,
              name: '📡 RelayChat ESP32',
              rssi: result.rssi,
              nativeDevice: result.device,
            );
          }
        }
      });

      await fbp.FlutterBluePlus.startScan(
        withServices: [fbp.Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E')],
        timeout: const Duration(seconds: 6),
      );
      await fbp.FlutterBluePlus.isScanning.where((val) => val == false).first;
      await scanSub.cancel();
    } catch (_) {}

    final devices = deviceMap.values.toList();
    devices.sort((a, b) => b.rssi.compareTo(a.rssi));
    return devices;
  }

  Future<bool> connectToDevice(RelayDevice device) async {
    _connectionProgressController.add(0.1);
    try {
      final nativeDevice = device.nativeDevice as fbp.BluetoothDevice?;
      if (nativeDevice == null) return false;

      await _cancelSubscriptions();
      _connectionProgressController.add(0.2);
      await nativeDevice.connect(license: fbp.License.nonprofit, timeout: const Duration(seconds: 10));
      
      if (Platform.isAndroid) {
        try {
          await nativeDevice.requestMtu(512);
        } catch (_) {}
      }
      
      _connSub = nativeDevice.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          if (_connectedDevice != null) {
             _connectedDevice = null;
             _rxBuffer.clear();
             _rxSub?.cancel();
            _rxSub = null;
            _deviceDisconnectedController.add(true);
          }
        }
      });
      
      _connectionProgressController.add(0.5);
      final services = await nativeDevice.discoverServices();
      _connectionProgressController.add(0.7);

      for (var service in services) {
        if (service.uuid.toString().toUpperCase().contains('6E400001')) {
          for (var char in service.characteristics) {
            final charUuid = char.uuid.toString().toUpperCase();
            if (charUuid.contains('6E400002')) _txCharacteristic = char;
            if (charUuid.contains('6E400003')) _rxCharacteristic = char;
          }
        }
      }

      _connectionProgressController.add(0.9);

      if (_rxCharacteristic != null) {
        await _rxCharacteristic!.setNotifyValue(true);
        _rxSub = _rxCharacteristic!.onValueReceived.listen(_handleIncomingBleBytes);
      }

      _connectionProgressController.add(1.0);
      _connectedDevice = device.copyWith(rssi: await nativeDevice.readRssi().catchError((_) => device.rssi));
      await saveLastDevice(device.id);
      _deviceConnectedController.add(_connectedDevice!);

      return true;
    } catch (e) {
      _connectionProgressController.add(0.0);
      return false;
    }
  }

  Future<void> disconnect() async {
    await _rxSub?.cancel();
    _rxSub = null;
    try {
      final nativeDevice = _connectedDevice?.nativeDevice as fbp.BluetoothDevice?;
      if (nativeDevice != null) await nativeDevice.disconnect();
    } catch (_) {}
    await _connSub?.cancel();
    _connSub = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
    _connectedDevice = null;
    _rxBuffer.clear();
  }

  // ──────────────────────────────────────────────────────────
  //  Frame Framing and Transmission
  // ──────────────────────────────────────────────────────────

  void _handleIncomingBleBytes(List<int> value) {
    if (value.isEmpty) return;
    _rxBuffer.add(value);

    while (_rxBuffer.length >= Frame.HEADER_SIZE) {
      final bytes = _rxBuffer.toBytes();
      
      // Resync to magic byte
      int magicIdx = bytes.indexOf(Frame.MAGIC_BYTE);
      if (magicIdx == -1) {
        _rxBuffer.clear(); // Garbage, drop everything
        return;
      }
      if (magicIdx > 0) {
        // Discard data before magic byte
        _rxBuffer.clear();
        _rxBuffer.add(bytes.sublist(magicIdx));
        continue;
      }

      // Check version
      if (bytes[1] != Frame.VERSION) {
        // Bad version, consume magic byte and retry resync
        _rxBuffer.clear();
        _rxBuffer.add(bytes.sublist(1));
        continue;
      }

      final bufferData = ByteData.sublistView(bytes);
      final payloadLength = bufferData.getUint16(69, Endian.little);
      final totalFrameLength = Frame.HEADER_SIZE + payloadLength;

      // Sanity check length
      if (payloadLength > Frame.MAX_PAYLOAD_SIZE) {
         _rxBuffer.clear();
         _rxBuffer.add(bytes.sublist(1));
         continue;
      }

      if (_rxBuffer.length < totalFrameLength) {
        // Wait for more chunks
        return;
      }

      // We have a full frame!
      final frameBytes = bytes.sublist(0, totalFrameLength);
      final frame = Frame.decode(frameBytes);
      if (frame != null) {
        _incomingFrameController.add(frame);
      }

      // Remove processed frame from buffer
      _rxBuffer.clear();
      _rxBuffer.add(bytes.sublist(totalFrameLength));
    }
  }

  Future<bool> sendFrame(Frame frame) async {
    if (_connectedDevice == null || _txCharacteristic == null) return false;

    try {
      final bytes = frame.encode();
      
      await _txCharacteristic!.write(
        bytes,
        withoutResponse: _txCharacteristic!.properties.writeWithoutResponse,
      );
      
      return true;
    } catch (e) {
      debugPrint('SendFrame error: $e');
      return false;
    }
  }

  void dispose() {
    _incomingFrameController.close();
    _connectionProgressController.close();
    _deviceDisconnectedController.close();
    _deviceConnectedController.close();
  }
}
