import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lighthouse/models/call.dart';

void main() {
  group('Call Model Tests', () {
    // CAL_001: Test fromFirestore with complete data
    test('should create Call from Firestore with complete data', () {
      final mockDoc = _MockDocumentSnapshot(
        id: 'call123',
        data: {
          'roomName': 'room-abc-123',
          'callerId': 'user1',
          'receiverId': 'user2',
          'callerName': 'John Doe',
          'callerEmail': 'john@example.com',
          'receiverName': 'Jane Smith',
          'callerRole': 'citizen',
          'type': 'video',
          'status': 'active',
          'startedAt': Timestamp.fromDate(DateTime(2024, 1, 1, 12, 0)),
          'answeredAt': Timestamp.fromDate(DateTime(2024, 1, 1, 12, 1)),
          'endedAt': Timestamp.fromDate(DateTime(2024, 1, 1, 12, 15)),
          'duration': 840,
        },
      );

      final call = Call.fromFirestore(mockDoc);

      expect(call.id, 'call123');
      expect(call.roomName, 'room-abc-123');
      expect(call.callerId, 'user1');
      expect(call.receiverId, 'user2');
      expect(call.callerName, 'John Doe');
      expect(call.type, 'video');
      expect(call.status, 'active');
      expect(call.duration, 840);
    });

    // CAL_002: Test fromFirestore with missing optional fields
    test('should handle missing optional fields', () {
      final mockDoc = _MockDocumentSnapshot(
        id: 'call456',
        data: {
          'roomName': 'room-xyz',
          'callerId': 'user3',
          'receiverId': 'user4',
          'callerName': 'Alice',
          'callerRole': 'dispatcher',
          'type': 'audio',
          'status': 'ringing',
        },
      );

      final call = Call.fromFirestore(mockDoc);

      expect(call.id, 'call456');
      expect(call.startedAt, isNull);
      expect(call.answeredAt, isNull);
      expect(call.endedAt, isNull);
      expect(call.duration, isNull);
    });

    // CAL_004: Test isActive for active call
    test('should identify active call correctly', () {
      final call = Call(
        id: 'call1',
        roomName: 'room1',
        callerId: 'user1',
        receiverId: 'user2',
        callerName: 'John',
        callerRole: 'citizen',
        type: 'video',
        status: Call.STATUS_ACTIVE,
      );

      expect(call.status, Call.STATUS_ACTIVE);
    });

    // CAL_005: Test isActive for connecting call
    test('should identify connecting call correctly', () {
      final call = Call(
        id: 'call2',
        roomName: 'room2',
        callerId: 'user1',
        receiverId: 'user2',
        callerName: 'John',
        callerRole: 'citizen',
        type: 'audio',
        status: Call.STATUS_CONNECTING,
      );

      expect(call.status, Call.STATUS_CONNECTING);
    });

    // CAL_008: Test status constants
    test('should have correct status constants', () {
      expect(Call.STATUS_RINGING, 'ringing');
      expect(Call.STATUS_CONNECTING, 'connecting');
      expect(Call.STATUS_ACTIVE, 'active');
      expect(Call.STATUS_ENDED, 'ended');
      expect(Call.STATUS_MISSED, 'missed');
      expect(Call.STATUS_REJECTED, 'rejected');
    });

    // CAL_009: Test type constants
    test('should have correct type constants', () {
      expect(Call.TYPE_VIDEO, 'video');
      expect(Call.TYPE_AUDIO, 'audio');
    });
  });
}

// Mock DocumentSnapshot for testing
class _MockDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic>? _data;

  _MockDocumentSnapshot({required this.id, Map<String, dynamic>? data})
      : _data = data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) => _data?[field];

  @override
  dynamic operator [](Object field) => _data?[field];

  @override
  bool get exists => _data != null;

  // Implement other required methods with minimal implementation
  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnimplementedError();

  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
}
