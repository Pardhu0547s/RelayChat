import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bluetooth_device.dart';
import '../services/bluetooth_service.dart';

class BluetoothProvider extends ChangeNotifier {
  final BluetoothService _service = BluetoothService();

  bool _isBluetoothEnabled = false;
  bool _isPermissionGranted = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  double _connectionProgress = 0.0;
  List<RelayDevice> _discoveredDevices = [];
  RelayDevice? _connectedDevice;
  bool _hasSavedDevice = false;

  StreamSubscription<double>? _progressSubscription;

  bool get isBluetoothEnabled => _isBluetoothEnabled;
  bool get isPermissionGranted => _isPermissionGranted;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  double get connectionProgress => _connectionProgress;
  List<RelayDevice> get discoveredDevices => _discoveredDevices;
  RelayDevice? get connectedDevice => _connectedDevice;
  bool get hasSavedDevice => _hasSavedDevice;
  Stream<bool> get deviceDisconnected => _service.deviceDisconnected;

  BluetoothProvider() {
    _init();
  }

  Future<void> _init() async {
    await checkStatusAndPermissions();
    _progressSubscription = _service.connectionProgress.listen((progress) {
      _connectionProgress = progress;
      notifyListeners();
    });
    
    // Check if we have a saved device
    final savedMac = await _service.getLastDeviceMac();
    _hasSavedDevice = savedMac != null && savedMac.isNotEmpty;
    notifyListeners();
  }

  Future<void> checkStatusAndPermissions() async {
    _isBluetoothEnabled = await _service.isBluetoothEnabled();
    _isPermissionGranted = await _service.checkPermissions();
    notifyListeners();
  }

  Future<void> requestPermissions() async {
    _isPermissionGranted = await _service.requestPermissions();
    _isBluetoothEnabled = await _service.isBluetoothEnabled();
    notifyListeners();
  }

  Future<void> turnOnBluetooth() async {
    await _service.turnOnBluetooth();
    // Wait a moment for adapter to turn on, then re-check
    await Future.delayed(const Duration(seconds: 1));
    await checkStatusAndPermissions();
  }

  Future<void> startScan() async {
    _isScanning = true;
    _discoveredDevices = [];
    notifyListeners();

    try {
      final devices = await _service.scanDevices();
      _discoveredDevices = devices;
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<bool> connectDevice(RelayDevice device) async {
    _isConnecting = true;
    _connectionProgress = 0.0;
    notifyListeners();

    final success = await _service.connectToDevice(device);
    _isConnecting = false;
    
    if (success) {
      _connectedDevice = _service.connectedDevice;
      _hasSavedDevice = true;
    }
    
    notifyListeners();
    return success;
  }

  /// Auto-connect to the last saved ESP32
  Future<bool> autoConnect() async {
    _isConnecting = true;
    _connectionProgress = 0.0;
    notifyListeners();

    final success = await _service.autoConnect();
    _isConnecting = false;

    if (success) {
      _connectedDevice = _service.connectedDevice;
    }

    notifyListeners();
    return success;
  }

  Future<void> disconnectDevice() async {
    await _service.disconnect();
    _connectedDevice = null;
    notifyListeners();
  }

  /// Forget the saved device (forces scan on next launch)
  Future<void> forgetDevice() async {
    await _service.clearSavedDevice();
    await disconnectDevice();
    _hasSavedDevice = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }
}
