class DiscoveredUser {
  final String phoneId;
  final String name;
  final String device;
  final DateTime lastSeen;

  DiscoveredUser({
    required this.phoneId,
    required this.name,
    required this.device,
    required this.lastSeen,
  });

  DiscoveredUser copyWith({
    String? phoneId,
    String? name,
    String? device,
    DateTime? lastSeen,
  }) {
    return DiscoveredUser(
      phoneId: phoneId ?? this.phoneId,
      name: name ?? this.name,
      device: device ?? this.device,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
