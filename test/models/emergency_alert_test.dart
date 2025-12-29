import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/models/emergency_alert.dart';

void main() {
  group('EmergencyAlert Model Tests', () {
    test('should create EmergencyAlert with required fields', () {
      final alert = EmergencyAlert(
        id: 'alert123',
        userId: 'user456',
        userEmail: 'user@example.com',
        lon: 101.6869,
        lat: 3.1390,
        services: ['police', 'ambulance'],
        description: 'Medical emergency',
        status: EmergencyAlert.STATUS_PENDING,
      );

      expect(alert.id, 'alert123');
      expect(alert.userId, 'user456');
      expect(alert.userEmail, 'user@example.com');
      expect(alert.lon, 101.6869);
      expect(alert.lat, 3.1390);
      expect(alert.services, ['police', 'ambulance']);
      expect(alert.description, 'Medical emergency');
      expect(alert.status, EmergencyAlert.STATUS_PENDING);
    });

    test('should correctly identify pending status', () {
      final pendingAlert = EmergencyAlert(
        id: 'alert1',
        userId: 'user1',
        userEmail: 'user1@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['police'],
        description: 'Help',
        status: EmergencyAlert.STATUS_PENDING,
      );

      expect(pendingAlert.isPending, isTrue);
      expect(pendingAlert.isActive, isFalse);
      expect(pendingAlert.isArrived, isFalse);
      expect(pendingAlert.isResolved, isFalse);
      expect(pendingAlert.isCancelled, isFalse);
    });

    test('should correctly identify active status', () {
      final activeAlert = EmergencyAlert(
        id: 'alert2',
        userId: 'user2',
        userEmail: 'user2@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['ambulance'],
        description: 'Emergency',
        status: EmergencyAlert.STATUS_ACTIVE,
        acceptedBy: 'dispatcher123',
        acceptedByEmail: 'dispatcher@test.com',
        acceptedAt: DateTime(2024, 1, 1, 12, 0),
      );

      expect(activeAlert.isPending, isFalse);
      expect(activeAlert.isActive, isTrue);
      expect(activeAlert.isArrived, isFalse);
      expect(activeAlert.isResolved, isFalse);
      expect(activeAlert.isCancelled, isFalse);
      expect(activeAlert.hasDispatcher, isTrue);
    });

    test('should correctly identify arrived status', () {
      final arrivedAlert = EmergencyAlert(
        id: 'alert3',
        userId: 'user3',
        userEmail: 'user3@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['fire'],
        description: 'Fire emergency',
        status: EmergencyAlert.STATUS_ARRIVED,
        acceptedBy: 'dispatcher456',
        acceptedByEmail: 'dispatcher2@test.com',
        acceptedAt: DateTime(2024, 1, 1, 12, 0),
        arrivedAt: DateTime(2024, 1, 1, 12, 15),
      );

      expect(arrivedAlert.isPending, isFalse);
      expect(arrivedAlert.isActive, isFalse);
      expect(arrivedAlert.isArrived, isTrue);
      expect(arrivedAlert.isResolved, isFalse);
      expect(arrivedAlert.isCancelled, isFalse);
    });

    test('should correctly identify resolved status', () {
      final resolvedAlert = EmergencyAlert(
        id: 'alert4',
        userId: 'user4',
        userEmail: 'user4@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['police'],
        description: 'Resolved emergency',
        status: EmergencyAlert.STATUS_RESOLVED,
        acceptedBy: 'dispatcher789',
        acceptedByEmail: 'dispatcher3@test.com',
        acceptedAt: DateTime(2024, 1, 1, 12, 0),
        arrivedAt: DateTime(2024, 1, 1, 12, 15),
        resolvedAt: DateTime(2024, 1, 1, 12, 30),
        resolutionNotes: 'Situation handled successfully',
      );

      expect(resolvedAlert.isPending, isFalse);
      expect(resolvedAlert.isActive, isFalse);
      expect(resolvedAlert.isArrived, isFalse);
      expect(resolvedAlert.isResolved, isTrue);
      expect(resolvedAlert.isCancelled, isFalse);
    });

    test('should correctly identify cancelled status', () {
      final cancelledAlert = EmergencyAlert(
        id: 'alert5',
        userId: 'user5',
        userEmail: 'user5@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['ambulance'],
        description: 'Cancelled emergency',
        status: EmergencyAlert.STATUS_CANCELLED,
        cancelledAt: DateTime(2024, 1, 1, 12, 5),
        cancellationReason: 'False alarm',
      );

      expect(cancelledAlert.isPending, isFalse);
      expect(cancelledAlert.isActive, isFalse);
      expect(cancelledAlert.isArrived, isFalse);
      expect(cancelledAlert.isResolved, isFalse);
      expect(cancelledAlert.isCancelled, isTrue);
    });

    test('should correctly identify hasDispatcher', () {
      final withoutDispatcher = EmergencyAlert(
        id: 'alert6',
        userId: 'user6',
        userEmail: 'user6@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['police'],
        description: 'No dispatcher yet',
        status: EmergencyAlert.STATUS_PENDING,
      );

      final withDispatcher = EmergencyAlert(
        id: 'alert7',
        userId: 'user7',
        userEmail: 'user7@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['ambulance'],
        description: 'Has dispatcher',
        status: EmergencyAlert.STATUS_ACTIVE,
        acceptedBy: 'dispatcher123',
      );

      expect(withoutDispatcher.hasDispatcher, isFalse);
      expect(withDispatcher.hasDispatcher, isTrue);
    });

    test('should handle multiple services', () {
      final alert = EmergencyAlert(
        id: 'alert8',
        userId: 'user8',
        userEmail: 'user8@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['police', 'ambulance', 'fire'],
        description: 'Major emergency',
        status: EmergencyAlert.STATUS_ACTIVE,
      );

      expect(alert.services, hasLength(3));
      expect(alert.services, contains('police'));
      expect(alert.services, contains('ambulance'));
      expect(alert.services, contains('fire'));
    });

    test('should handle datetime fields correctly', () {
      final createdTime = DateTime(2024, 1, 1, 12, 0);
      final acceptedTime = DateTime(2024, 1, 1, 12, 5);
      final arrivedTime = DateTime(2024, 1, 1, 12, 15);

      final alert = EmergencyAlert(
        id: 'alert9',
        userId: 'user9',
        userEmail: 'user9@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['ambulance'],
        description: 'Time test',
        status: EmergencyAlert.STATUS_ARRIVED,
        createdAt: createdTime,
        acceptedAt: acceptedTime,
        arrivedAt: arrivedTime,
      );

      expect(alert.createdAt, createdTime);
      expect(alert.acceptedAt, acceptedTime);
      expect(alert.arrivedAt, arrivedTime);
    });

    test('should handle optional fields as null', () {
      final alert = EmergencyAlert(
        id: 'alert10',
        userId: 'user10',
        userEmail: 'user10@test.com',
        lon: 101.0,
        lat: 3.0,
        services: ['police'],
        description: 'Minimal alert',
        status: EmergencyAlert.STATUS_PENDING,
      );

      expect(alert.createdAt, isNull);
      expect(alert.acceptedBy, isNull);
      expect(alert.acceptedByEmail, isNull);
      expect(alert.acceptedAt, isNull);
      expect(alert.arrivedAt, isNull);
      expect(alert.resolvedAt, isNull);
      expect(alert.resolutionNotes, isNull);
      expect(alert.cancelledAt, isNull);
      expect(alert.cancellationReason, isNull);
    });
  });
}
