/// Model for emergency alerts shown on the map
class EmergencyAlert {
  // Status constants
  static const String STATUS_PENDING = 'pending';
  static const String STATUS_ACTIVE = 'active';
  static const String STATUS_ARRIVED = 'arrived';
  static const String STATUS_RESOLVED = 'resolved';
  static const String STATUS_CANCELLED = 'cancelled';

  final String id;
  final String userId;
  final String userEmail;
  final double lon;
  final double lat;
  final List<String> services;
  final String description;
  final String status;
  final DateTime? createdAt;

  // Dispatcher acceptance info
  final String? acceptedBy;
  final String? acceptedByEmail;
  final DateTime? acceptedAt;

  // Arrival info
  final DateTime? arrivedAt;

  // Resolution info
  final DateTime? resolvedAt;
  final String? resolutionNotes;

  // Cancellation info
  final DateTime? cancelledAt;
  final String? cancellationReason;

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
    this.acceptedBy,
    this.acceptedByEmail,
    this.acceptedAt,
    this.arrivedAt,
    this.resolvedAt,
    this.resolutionNotes,
    this.cancelledAt,
    this.cancellationReason,
  });

  /// Check if alert is pending (waiting for dispatcher)
  bool get isPending => status == STATUS_PENDING;

  /// Check if alert is active (dispatcher accepted)
  bool get isActive => status == STATUS_ACTIVE;

  /// Check if dispatcher has arrived
  bool get isArrived => status == STATUS_ARRIVED;

  /// Check if alert is resolved
  bool get isResolved => status == STATUS_RESOLVED;

  /// Check if alert is cancelled
  bool get isCancelled => status == STATUS_CANCELLED;

  /// Check if alert has been accepted by a dispatcher
  bool get hasDispatcher => acceptedBy != null && acceptedBy!.isNotEmpty;
}
