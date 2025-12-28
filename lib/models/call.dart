import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing a voice or video call between dispatcher and citizen
class Call {
  final String id;
  final String roomName;
  final String callerId;
  final String receiverId;
  final String callerName;
  final String? callerEmail;
  final String callerRole; // 'dispatcher' or 'citizen'
  final String type; // 'video' or 'audio'
  final String status; // 'ringing', 'connecting', 'active', 'ended', 'missed', 'rejected'
  final DateTime? startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int? duration; // in seconds

  // Call status constants
  static const String STATUS_RINGING = 'ringing';
  static const String STATUS_CONNECTING = 'connecting';
  static const String STATUS_ACTIVE = 'active';
  static const String STATUS_ENDED = 'ended';
  static const String STATUS_MISSED = 'missed';
  static const String STATUS_REJECTED = 'rejected';

  // Call type constants
  static const String TYPE_VIDEO = 'video';
  static const String TYPE_AUDIO = 'audio';

  Call({
    required this.id,
    required this.roomName,
    required this.callerId,
    required this.receiverId,
    required this.callerName,
    this.callerEmail,
    required this.callerRole,
    required this.type,
    required this.status,
    this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.duration,
  });

  /// Create Call from Firestore document
  factory Call.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Call(
      id: doc.id,
      roomName: data['roomName'] ?? '',
      callerId: data['callerId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      callerName: data['callerName'] ?? 'Unknown',
      callerEmail: data['callerEmail'],
      callerRole: data['callerRole'] ?? 'citizen',
      type: data['type'] ?? TYPE_AUDIO,
      status: data['status'] ?? STATUS_RINGING,
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      answeredAt: (data['answeredAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      duration: data['duration'],
    );
  }

  /// Convert Call to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'roomName': roomName,
      'callerId': callerId,
      'receiverId': receiverId,
      'callerName': callerName,
      'callerEmail': callerEmail,
      'callerRole': callerRole,
      'type': type,
      'status': status,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'answeredAt': answeredAt != null ? Timestamp.fromDate(answeredAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'duration': duration,
    };
  }

  /// Create a copy with updated fields
  Call copyWith({
    String? id,
    String? roomName,
    String? callerId,
    String? receiverId,
    String? callerName,
    String? callerEmail,
    String? callerRole,
    String? type,
    String? status,
    DateTime? startedAt,
    DateTime? answeredAt,
    DateTime? endedAt,
    int? duration,
  }) {
    return Call(
      id: id ?? this.id,
      roomName: roomName ?? this.roomName,
      callerId: callerId ?? this.callerId,
      receiverId: receiverId ?? this.receiverId,
      callerName: callerName ?? this.callerName,
      callerEmail: callerEmail ?? this.callerEmail,
      callerRole: callerRole ?? this.callerRole,
      type: type ?? this.type,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
    );
  }

  /// Check if call is currently active or connecting
  bool get isActive => status == STATUS_ACTIVE || status == STATUS_CONNECTING;

  /// Check if call is ringing (incoming)
  bool get isRinging => status == STATUS_RINGING;

  /// Check if call has ended
  bool get hasEnded => status == STATUS_ENDED || status == STATUS_MISSED || status == STATUS_REJECTED;

  /// Get human-readable status text
  String get statusText {
    switch (status) {
      case STATUS_RINGING:
        return 'Ringing...';
      case STATUS_CONNECTING:
        return 'Connecting...';
      case STATUS_ACTIVE:
        return 'Active';
      case STATUS_ENDED:
        return 'Ended';
      case STATUS_MISSED:
        return 'Missed';
      case STATUS_REJECTED:
        return 'Rejected';
      default:
        return status;
    }
  }

  /// Get call duration as formatted string (MM:SS)
  String get durationFormatted {
    if (duration == null) return '00:00';
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
