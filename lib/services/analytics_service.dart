import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service for generating analytics and metrics from emergency alert data
class AnalyticsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get total alerts count for a time period
  Future<int> getTotalAlerts({required DateTime startDate, DateTime? endDate}) async {
    try {
      final end = endDate ?? DateTime.now();

      final query = await _firestore
          .collection('emergency_alerts')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      debugPrint('[AnalyticsService] Total alerts query returned ${query.docs.length} docs');
      return query.docs.length;
    } catch (e) {
      debugPrint('[AnalyticsService] Error getting total alerts: $e');
      return 0;
    }
  }

  /// Get alerts by status breakdown
  Future<Map<String, int>> getAlertsByStatus({required DateTime startDate, DateTime? endDate}) async {
    try {
      final end = endDate ?? DateTime.now();

      final query = await _firestore
          .collection('emergency_alerts')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      final Map<String, int> statusCounts = {
        'pending': 0,
        'active': 0,
        'arrived': 0,
        'resolved': 0,
        'cancelled': 0,
      };

      for (var doc in query.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'pending';
        if (statusCounts.containsKey(status)) {
          statusCounts[status] = (statusCounts[status] ?? 0) + 1;
        }
      }

      return statusCounts;
    } catch (e) {
      debugPrint('[AnalyticsService] Error getting alerts by status: $e');
      return {};
    }
  }

  /// Calculate average response time (time from alert creation to dispatcher acceptance)
  Future<double> getAverageResponseTime({required DateTime startDate, DateTime? endDate}) async {
    try {
      final end = endDate ?? DateTime.now();

      final query = await _firestore
          .collection('emergency_alerts')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .where('status', whereIn: ['active', 'arrived', 'resolved'])
          .get();

      if (query.docs.isEmpty) {
        debugPrint('[AnalyticsService] No alerts with status active/arrived/resolved');
        return 0.0;
      }

      double totalResponseTime = 0;
      int count = 0;

      for (var doc in query.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;
        final acceptedAt = data['acceptedAt'] as Timestamp?;

        if (createdAt != null && acceptedAt != null) {
          final responseTime = acceptedAt.toDate().difference(createdAt.toDate()).inSeconds;
          totalResponseTime += responseTime;
          count++;
        }
      }

      debugPrint('[AnalyticsService] Calculated avg response time: ${count > 0 ? totalResponseTime / count : 0.0}s from $count alerts');
      return count > 0 ? totalResponseTime / count : 0.0;
    } catch (e) {
      debugPrint('[AnalyticsService] Error calculating average response time: $e');
      return 0.0;
    }
  }

  /// Get alert counts per day for the last N days
  Future<Map<DateTime, int>> getAlertTrend({int days = 7}) async {
    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));

      final query = await _firestore
          .collection('emergency_alerts')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .get();

      final Map<DateTime, int> dailyCounts = {};

      // Initialize all days to 0
      for (int i = 0; i < days; i++) {
        final date = startDate.add(Duration(days: i));
        final dateKey = DateTime(date.year, date.month, date.day);
        dailyCounts[dateKey] = 0;
      }

      // Count alerts per day
      for (var doc in query.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;

        if (createdAt != null) {
          final date = createdAt.toDate();
          final dateKey = DateTime(date.year, date.month, date.day);

          if (dailyCounts.containsKey(dateKey)) {
            dailyCounts[dateKey] = (dailyCounts[dateKey] ?? 0) + 1;
          }
        }
      }

      debugPrint('[AnalyticsService] Alert trend: $dailyCounts');
      return dailyCounts;
    } catch (e) {
      debugPrint('[AnalyticsService] Error getting alert trend: $e');
      return {};
    }
  }

  /// Get top dispatchers by number of resolved alerts
  Future<List<Map<String, dynamic>>> getTopDispatchers({int limit = 5}) async {
    try {
      final query = await _firestore
          .collection('emergency_alerts')
          .where('status', isEqualTo: 'resolved')
          .get();

      final Map<String, Map<String, dynamic>> dispatcherStats = {};

      for (var doc in query.docs) {
        final data = doc.data();
        final dispatcherId = data['acceptedBy'] as String?;
        final dispatcherEmail = data['acceptedByEmail'] as String?;
        final createdAt = data['createdAt'] as Timestamp?;
        final acceptedAt = data['acceptedAt'] as Timestamp?;

        if (dispatcherId != null && dispatcherEmail != null) {
          if (!dispatcherStats.containsKey(dispatcherId)) {
            dispatcherStats[dispatcherId] = {
              'id': dispatcherId,
              'email': dispatcherEmail,
              'alertsResolved': 0,
              'totalResponseTime': 0.0,
              'averageResponseTime': 0.0,
            };
          }

          dispatcherStats[dispatcherId]!['alertsResolved'] += 1;

          // Calculate response time if both timestamps exist
          if (createdAt != null && acceptedAt != null) {
            final responseTime = acceptedAt.toDate().difference(createdAt.toDate()).inSeconds.toDouble();
            dispatcherStats[dispatcherId]!['totalResponseTime'] += responseTime;
          }
        }
      }

      // Calculate averages and convert to list
      final dispatcherList = dispatcherStats.values.map((stats) {
        final alertsResolved = stats['alertsResolved'] as int;
        final totalResponseTime = stats['totalResponseTime'] as double;

        stats['averageResponseTime'] = alertsResolved > 0
            ? totalResponseTime / alertsResolved
            : 0.0;

        return stats;
      }).toList();

      // Sort by alerts resolved (descending)
      dispatcherList.sort((a, b) =>
        (b['alertsResolved'] as int).compareTo(a['alertsResolved'] as int)
      );

      return dispatcherList.take(limit).toList();
    } catch (e) {
      debugPrint('[AnalyticsService] Error getting top dispatchers: $e');
      return [];
    }
  }

  /// Get count of active dispatchers (users with role=dispatcher and isActive=true)
  Future<int> getActiveDispatchersCount() async {
    try {
      final query = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'dispatcher')
          .where('isActive', isEqualTo: true)
          .get();

      return query.docs.length;
    } catch (e) {
      debugPrint('[AnalyticsService] Error getting active dispatchers: $e');
      return 0;
    }
  }

  /// Calculate success rate (resolved / total non-cancelled alerts)
  Future<double> getSuccessRate({required DateTime startDate, DateTime? endDate}) async {
    try {
      final end = endDate ?? DateTime.now();

      final query = await _firestore
          .collection('emergency_alerts')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      if (query.docs.isEmpty) return 0.0;

      int total = 0;
      int resolved = 0;

      for (var doc in query.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'pending';

        if (status != 'cancelled') {
          total++;
          if (status == 'resolved') {
            resolved++;
          }
        }
      }

      return total > 0 ? (resolved / total) * 100 : 0.0;
    } catch (e) {
      debugPrint('[AnalyticsService] Error calculating success rate: $e');
      return 0.0;
    }
  }
}
