class RelayDevice {
  final String id;
  final String name;
  final int rssi;
  final bool isAvailable;
  final String batteryLevel;
  final String firmwareVersion;
  final dynamic nativeDevice; // Dynamic reference to physical BluetoothDevice if available

  RelayDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.isAvailable = true,
    this.batteryLevel = 'N/A',
    this.firmwareVersion = '1.0',
    this.nativeDevice,
  });

  /// Helper to convert RSSI value into visually striking signal bar string: ████████
  String get signalBar {
    if (rssi >= -50) return '████████';
    if (rssi >= -65) return '██████░░';
    if (rssi >= -80) return '████░░░░';
    if (rssi >= -90) return '██░░░░░░';
    return '█░░░░░░░';
  }

  RelayDevice copyWith({
    String? id,
    String? name,
    int? rssi,
    bool? isAvailable,
    String? batteryLevel,
    String? firmwareVersion,
    dynamic nativeDevice,
  }) {
    return RelayDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      isAvailable: isAvailable ?? this.isAvailable,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      nativeDevice: nativeDevice ?? this.nativeDevice,
    );
  }
}
