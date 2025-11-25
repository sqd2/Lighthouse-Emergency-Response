/// Model for emergency alerts shown on the map
class EmergencyAlert {
  final String id;
  final String userId;
  final String userEmail;
  final double lon;
  final double lat;
  final List<String> services;
  final String description;
  final String status;
  final DateTime? createdAt;

  const EmergencyAlert({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.lon,
    required this.lat,
    required this.services,
    required this.description,
    required this.status,
    this.createdAt,
  });
}
