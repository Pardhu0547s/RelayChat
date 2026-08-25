import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';
import '../models/bluetooth_device.dart';

/// BluetoothService encapsulates real BLE operations.
/// UI never talks directly to Bluetooth — it goes through this service layer.
class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  final StreamController<String> _incomingMessageController = StreamController<String>.broadcast();
  Stream<String> get incomingMessages => _incomingMessageController.stream;

  final StreamController<double> _connectionProgressController = StreamController<double>.broadcast();
  Stream<double> get connectionProgress => _connectionProgressController.stream;

  final StreamController<bool> _deviceDisconnectedController = StreamController<bool>.broadcast();
  Stream<bool> get deviceDisconnected => _deviceDisconnectedController.stream;

  RelayDevice? _connectedDevice;
  RelayDevice? get connectedDevice => _connectedDevice;

  fbp.BluetoothCharacteristic? _txCharacteristic;
  fbp.BluetoothCharacteristic? _rxCharacteristic;

  // ──────────────────────────────────────────────────────────
  //  Permissions & Bluetooth Status
  // ──────────────────────────────────────────────────────────

  Future<bool> checkPermissions() async {
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return true;
    }

    if (Platform.isAndroid) {
      final bluetoothScan = await Permission.bluetoothScan.status;
      final bluetoothConnect = await Permission.bluetoothConnect.status;
      final location = await Permission.locationWhenInUse.status;

      // Android 12+ uses bluetoothScan + bluetoothConnect
      if (bluetoothScan.isGranted && bluetoothConnect.isGranted) {
        return true;
      }
      // Android 11 and below uses location
      if (location.isGranted) {
        return true;
      }
      return false;
    }

    if (Platform.isIOS) {
      final status = await Permission.bluetooth.status;
      return status.isGranted;
    }

    return true;
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return true;
    }

    if (Platform.isAndroid) {
      // Request all BLE-related permissions — this triggers the OS popup dialogs
      final Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ].request();

      // Check if we got enough permissions
      final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final locationOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

      // Android 12+: need scan + connect. Android 11-: need location.
      if ((scanOk && connectOk) || locationOk) {
        return true;
      }

      // If permanently denied, guide user to app settings
      final anyPermanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
      if (anyPermanentlyDenied) {
        await openAppSettings();
        // Re-check after returning from settings
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
    if (kIsWeb || Platform.isLinux) {
      return true;
    }
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
      } catch (e) {
        debugPrint('Could not turn on Bluetooth: $e');
      }
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Scan Devices — REAL BLE ONLY, no dummy devices
  // ──────────────────────────────────────────────────────────

  Future<List<RelayDevice>> scanDevices() async {
    final Map<String, RelayDevice> deviceMap = {};

    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return [];
    }

    try {
      // Stop any previous scan
      if (fbp.FlutterBluePlus.isScanningNow) {
        await fbp.FlutterBluePlus.stopScan();
      }

      // Listen to scan results stream and collect devices in real-time
      StreamSubscription? scanSub;

      scanSub = fbp.FlutterBluePlus.onScanResults.listen((results) {
        for (var result in results) {
          final id = result.device.remoteId.str;

          // Check if the device advertises our specific service UUID
          final serviceUuids = result.advertisementData.serviceUuids
              .map((g) => g.toString().toUpperCase())
              .toList();
          
          final bool isRelayChatDevice = serviceUuids.contains('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');

          if (!isRelayChatDevice) continue;

          // Force display name for confirmed RelayChat devices
          final deviceName = '📡 RelayChat ESP32';

          // Update or add device (keeps strongest RSSI reading)
          if (!deviceMap.containsKey(id) || result.rssi > (deviceMap[id]?.rssi ?? -999)) {
            deviceMap[id] = RelayDevice(
              id: id,
              name: deviceName,
              rssi: result.rssi,
              isAvailable: true,
              batteryLevel: 'N/A',
              firmwareVersion: '1.0',
              nativeDevice: result.device,
            );
          }
        }
      }, onError: (e) {
        debugPrint('Scan stream error: $e');
      });

      // Start scanning — don't await, it returns immediately
      await fbp.FlutterBluePlus.startScan(
        withServices: [fbp.Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E')],
        timeout: const Duration(seconds: 6),
        androidUsesFineLocation: true,
      );

      // Wait for scan to finish (timeout fires after 6 seconds)
      await fbp.FlutterBluePlus.isScanning.where((val) => val == false).first;

      // Clean up stream subscription
      await scanSub.cancel();
    } catch (e) {
      debugPrint('BLE Scan error: $e');
    }

    // Sort by signal strength (strongest first)
    final devices = deviceMap.values.toList();
    devices.sort((a, b) => b.rssi.compareTo(a.rssi));
    return devices;
  }

  // ──────────────────────────────────────────────────────────
  //  Connect to ESP32 via real BLE
  // ──────────────────────────────────────────────────────────

  Future<bool> connectToDevice(RelayDevice device) async {
    _connectionProgressController.add(0.1);

    try {
      final nativeDevice = device.nativeDevice as fbp.BluetoothDevice?;
      if (nativeDevice == null) {
        // Fallback: simulated progress for non-native devices
        for (int i = 2; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 180));
          _connectionProgressController.add(i / 10.0);
        }
        _connectedDevice = device;
        return true;
      }

      _connectionProgressController.add(0.2);

      // Connect to physical BLE device
      await nativeDevice.connect(
        license: fbp.License.nonprofit,
        timeout: const Duration(seconds: 10),
      );
      
      // Listen for unexpected disconnections
      nativeDevice.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          if (_connectedDevice != null) {
             _connectedDevice = null;
             _deviceDisconnectedController.add(true);
          }
        }
      });
      
      _connectionProgressController.add(0.5);

      // Discover services
      final services = await nativeDevice.discoverServices();
      _connectionProgressController.add(0.7);

      // Find the UART service and characteristics
      for (var service in services) {
        if (service.uuid.toString().toUpperCase().contains('6E400001')) {
          for (var char in service.characteristics) {
            final charUuid = char.uuid.toString().toUpperCase();
            if (charUuid.contains('6E400002')) {
              _txCharacteristic = char; // Phone writes to this
            }
            if (charUuid.contains('6E400003')) {
              _rxCharacteristic = char; // Phone reads from this
            }
          }
        }
      }

      _connectionProgressController.add(0.9);

      // Enable notifications on RX characteristic to receive ESP32 replies
      if (_rxCharacteristic != null) {
        await _rxCharacteristic!.setNotifyValue(true);
        _rxCharacteristic!.onValueReceived.listen((value) {
          final receivedText = String.fromCharCodes(value);
          if (receivedText.isNotEmpty) {
            _incomingMessageController.add(receivedText);
          }
        });
      }

      _connectionProgressController.add(1.0);

      // Update device with real RSSI
      _connectedDevice = device.copyWith(
        rssi: await nativeDevice.readRssi().catchError((_) => device.rssi),
      );

      return true;
    } catch (e) {
      debugPrint('BLE Connect error: $e');
      _connectionProgressController.add(0.0);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      final nativeDevice = _connectedDevice?.nativeDevice as fbp.BluetoothDevice?;
      if (nativeDevice != null) {
        await nativeDevice.disconnect();
      }
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
    _txCharacteristic = null;
    _rxCharacteristic = null;
    _connectedDevice = null;
  }

  // ──────────────────────────────────────────────────────────
  //  Send & Receive Text via real BLE UART
  // ──────────────────────────────────────────────────────────

  Future<bool> sendMessage(String text) async {
    if (_connectedDevice == null) return false;

    try {
      if (_txCharacteristic != null) {
        // Send text over real BLE UART
        await _txCharacteristic!.write(
          text.codeUnits,
          withoutResponse: _txCharacteristic!.properties.writeWithoutResponse,
        );
        return true;
      } else {
        debugPrint('TX Characteristic not found — cannot send message');
        return false;
      }
    } catch (e) {
      debugPrint('BLE Send error: $e');
      return false;
    }
  }

  void dispose() {
    _incomingMessageController.close();
    _connectionProgressController.close();
    _deviceDisconnectedController.close();
  }
}
