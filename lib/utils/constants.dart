class AppConstants {
  static const String appName = 'RelayChat';
  static const String appTagline = 'Offline Communication';
  static const String logoPath = 'assets/logo/logo.png';
  
  // Navigation Routes
  static const String routeSplash = '/';
  static const String routeBluetoothStatus = '/bluetooth_status';
  static const String routeScanner = '/scanner';
  static const String routeConnecting = '/connecting';
  static const String routeConnectedDevice = '/connected_device';
  static const String routeChat = '/chat';
  
  // Bluetooth Service UUIDs (Sample RelayChat BLE Service)
  static const String serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String txCharUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String rxCharUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
}
