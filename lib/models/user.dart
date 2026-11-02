class DiscoveredUser {
  final String phoneId;
  final String name;
  final String device;
  final DateTime lastSeen;
  final int rssi;
  final double distance;

  DiscoveredUser({
    required this.phoneId,
    required this.name,
    required this.device,
    required this.lastSeen,
    this.rssi = 0,
    this.distance = 0.0,
  });

  DiscoveredUser copyWith({
    String? phoneId,
    String? name,
    String? device,
    DateTime? lastSeen,
    int? rssi,
    double? distance,
  }) {
    return DiscoveredUser(
      phoneId: phoneId ?? this.phoneId,
      name: name ?? this.name,
      device: device ?? this.device,
      lastSeen: lastSeen ?? this.lastSeen,
      rssi: rssi ?? this.rssi,
      distance: distance ?? this.distance,
    );
  }

  Map<String, dynamic> toJson() => {
    'phoneId': phoneId,
    'name': name,
    'device': device,
    'lastSeen': lastSeen.toIso8601String(),
    'rssi': rssi,
    'distance': distance,
  };

  factory DiscoveredUser.fromJson(Map<String, dynamic> json) => DiscoveredUser(
    phoneId: json['phoneId'] as String? ?? '',
    name: json['name'] as String? ?? 'User',
    device: json['device'] as String? ?? '',
    lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
    rssi: json['rssi'] as int? ?? 0,
    distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
  );
}
