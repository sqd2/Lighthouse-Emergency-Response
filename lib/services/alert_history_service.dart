import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/emergency_alert.dart';

/// Service for querying alert history with date filtering
class AlertHistoryService {
  static final _firestore = FirebaseFirestore.instance;

  /// Get past alerts for a specific dispatcher (only their accepted ones)
  static Stream<List<EmergencyAlert>> getDispatcherPastAlerts(
    String dispatcherId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 7));
    final end = endDate ?? DateTime.now();

    // Server-side filtering with date range (requires composite index)
    Query query = _firestore
        .collection('emergency_alerts')
        .where('acceptedBy', isEqualTo: dispatcherId)
        .where('status', whereIn: [
          EmergencyAlert.STATUS_RESOLVED,
          EmergencyAlert.STATUS_CANCELLED,
        ])
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end.add(const Duration(days: 1))))
        .orderBy('createdAt', descending: true)
        .limit(50);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => _alertFromDoc(doc)).toList();
    });
  }

  /// Get pending alerts (unassigned)
  static Stream<List<EmergencyAlert>> getPendingAlerts() {
    return _firestore
        .collection('emergency_alerts')
        .where('status', isEqualTo: EmergencyAlert.STATUS_PENDING)
        .orderBy('createdAt', descending: false) // Oldest first (FIFO)
        .limit(20)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return _alertFromDoc(doc);
      }).toList();
    });
  }

  /// Get active alerts for a specific dispatcher (only their current ones)
  static Stream<List<EmergencyAlert>> getDispatcherActiveAlerts(
    String dispatcherId,
  ) {
    return _firestore
        .collection('emergency_alerts')
        .where('acceptedBy', isEqualTo: dispatcherId)
        .where('status', whereIn: [
          EmergencyAlert.STATUS_ACTIVE,
          EmergencyAlert.STATUS_ARRIVED,
        ])
        .orderBy('acceptedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return _alertFromDoc(doc);
      }).toList();
    });
  }

  /// Get past alerts for a specific citizen
  static Stream<List<EmergencyAlert>> getCitizenPastAlerts(
    String citizenId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 7));
    final end = endDate ?? DateTime.now();

    // Server-side filtering with date range (requires composite index)
    Query query = _firestore
        .collection('emergency_alerts')
        .where('userId', isEqualTo: citizenId)
        .where('status', whereIn: [
          EmergencyAlert.STATUS_RESOLVED,
          EmergencyAlert.STATUS_CANCELLED,
        ])
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end.add(const Duration(days: 1))))
        .orderBy('createdAt', descending: true)
        .limit(50);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => _alertFromDoc(doc)).toList();
    });
  }

  /// Get active alerts for a specific citizen
  static Stream<List<EmergencyAlert>> getCitizenActiveAlerts(
    String citizenId,
  ) {
    return _firestore
        .collection('emergency_alerts')
        .where('userId', isEqualTo: citizenId)
        .where('status', whereIn: [
          EmergencyAlert.STATUS_PENDING,
          EmergencyAlert.STATUS_ACTIVE,
          EmergencyAlert.STATUS_ARRIVED,
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return _alertFromDoc(doc);
      }).toList();
    });
  }

  /// Check if dispatcher has any active alerts
  static Future<bool> hasActiveAlerts(String dispatcherId) async {
    final snapshot = await _firestore
        .collection('emergency_alerts')
        .where('acceptedBy', isEqualTo: dispatcherId)
        .where('status', whereIn: [
          EmergencyAlert.STATUS_ACTIVE,
          EmergencyAlert.STATUS_ARRIVED,
        ])
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  /// Helper to convert Firestore document to EmergencyAlert
  static EmergencyAlert _alertFromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    double lat = 0.0, lon = 0.0;
    final loc = data['location'];
    if (loc is GeoPoint) {
      lat = loc.latitude;
      lon = loc.longitude;
    }

    final services = (data['services'] as List?)?.map((s) => s.toString()).toList() ?? [];
    final createdAtTimestamp = data['createdAt'] as Timestamp?;
    final createdAt = createdAtTimestamp?.toDate();

    return EmergencyAlert(
      id: doc.id,
      userId: data['userId']?.toString() ?? '',
      userEmail: data['userEmail']?.toString() ?? 'Unknown',
      lon: lon,
      lat: lat,
      services: services,
      description: data['description']?.toString() ?? '',
      status: data['status']?.toString() ?? EmergencyAlert.STATUS_PENDING,
      createdAt: createdAt,
      acceptedBy: data['acceptedBy']?.toString(),
      acceptedByEmail: data['acceptedByEmail']?.toString(),
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
      arrivedAt: (data['arrivedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
      resolutionNotes: data['resolutionNotes']?.toString(),
      cancellationReason: data['cancellationReason']?.toString(),
    );
  }
}
