import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../config/livekit_config.dart';
import '../models/call.dart';
import 'dart:js' as js;

/// Service for managing LiveKit WebRTC calls
class LiveKitService extends ChangeNotifier {
  static final LiveKitService _instance = LiveKitService._internal();
  factory LiveKitService() => _instance;

  LiveKitService._internal() {
    // Clean up any stale state on initialization
    _cleanupStaleState();
  }

  /// Clean up stale state from previous sessions
  void _cleanupStaleState() {
    try {
      debugPrint('[LiveKitService] Cleaning up stale state');
      _room?.disconnect();
      _room?.dispose();
      _room = null;
      _currentCall = null;
      _callSubscription?.cancel();
      _callSubscription = null;
      _localVideoTrack = null;
      _localAudioTrack = null;
      _remoteVideoTrack = null;
      _remoteAudioTrack = null;
      _isMuted = false;
      _isVideoEnabled = true;
      _isSpeakerOn = true;
      debugPrint('[LiveKitService] Cleanup complete');
    } catch (e) {
      debugPrint('[LiveKitService] Error during cleanup: $e');
      // Don't crash, just log the error
    }
  }

  // LiveKit room instance
  Room? _room;
  Room? get room => _room;

  // Call state
  Call? _currentCall;
  Call? get currentCall => _currentCall;

  // Listeners
  StreamSubscription? _callSubscription;
  final StreamController<Call?> _callStateController = StreamController<Call?>.broadcast();
  Stream<Call?> get callStateStream => _callStateController.stream;

  // Track state
  LocalVideoTrack? _localVideoTrack;
  LocalAudioTrack? _localAudioTrack;
  RemoteVideoTrack? _remoteVideoTrack;
  RemoteAudioTrack? _remoteAudioTrack;

  LocalVideoTrack? get localVideoTrack => _localVideoTrack;
  LocalAudioTrack? get localAudioTrack => _localAudioTrack;
  RemoteVideoTrack? get remoteVideoTrack => _remoteVideoTrack;
  RemoteAudioTrack? get remoteAudioTrack => _remoteAudioTrack;

  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = true;

  bool get isMuted => _isMuted;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isSpeakerOn => _isSpeakerOn;

  /// Initialize call and create call document in Firestore
  Future<Call?> initiateCall({
    required String alertId,
    required String receiverId,
    required String receiverName,
    required String type, // 'video' or 'audio'
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Prevent calling yourself
      if (user.uid == receiverId) {
        debugPrint('[LiveKitService] Cannot call yourself');
        return null;
      }

      // Get current user data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data();
      final callerName = userData?['name'] ?? user.email ?? 'Unknown';
      final callerEmail = userData?['email'] ?? user.email ?? 'Unknown';
      final callerRole = userData?['role'] ?? 'citizen';

      // Generate unique room name
      final roomName = 'call_${alertId}_${DateTime.now().millisecondsSinceEpoch}';

      // Create call document in Firestore
      final callRef = await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .collection('calls')
          .add({
        'roomName': roomName,
        'callerId': user.uid,
        'receiverId': receiverId,
        'callerName': callerName,
        'callerEmail': callerEmail,
        'callerRole': callerRole,
        'type': type,
        'status': Call.STATUS_RINGING,
        'startedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[LiveKitService] Call initiated: ${callRef.id}');

      // Listen to call status updates
      _listenToCallUpdates(alertId, callRef.id);

      return Call(
        id: callRef.id,
        roomName: roomName,
        callerId: user.uid,
        receiverId: receiverId,
        callerName: callerName,
        callerRole: callerRole,
        type: type,
        status: Call.STATUS_RINGING,
        startedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[LiveKitService] Error initiating call: $e');
      return null;
    }
  }

  /// Accept an incoming call
  Future<bool> acceptCall(String alertId, Call call) async {
    try {
      debugPrint('[LiveKitService] Accepting call: ${call.id}');

      // Update call status to connecting
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .collection('calls')
          .doc(call.id)
          .update({
        'status': Call.STATUS_CONNECTING,
        'answeredAt': FieldValue.serverTimestamp(),
      });

      // Join the LiveKit room
      await joinRoom(alertId, call);

      return true;
    } catch (e) {
      debugPrint('[LiveKitService] Error accepting call: $e');

      // If join failed, mark call as rejected
      try {
        await FirebaseFirestore.instance
            .collection('emergency_alerts')
            .doc(alertId)
            .collection('calls')
            .doc(call.id)
            .update({
          'status': Call.STATUS_REJECTED,
          'endedAt': FieldValue.serverTimestamp(),
        });
      } catch (updateError) {
        debugPrint('[LiveKitService] Error updating call status after join failure: $updateError');
      }

      return false;
    }
  }

  /// Reject an incoming call
  Future<void> rejectCall(String alertId, String callId) async {
    try {
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .collection('calls')
          .doc(callId)
          .update({
        'status': Call.STATUS_REJECTED,
        'endedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[LiveKitService] Call rejected: $callId');
    } catch (e) {
      debugPrint('[LiveKitService] Error rejecting call: $e');
    }
  }

  /// Join a LiveKit room
  Future<void> joinRoom(String alertId, Call call) async {
    // Prevent duplicate joins - check if already connected or connecting
    if (_room != null) {
      debugPrint('[LiveKitService] Already in a room, skipping join');
      return;
    }

    try {
      debugPrint('[LiveKitService] Joining room: ${call.roomName}');

      // Get LiveKit token from Cloud Function
      final functions = FirebaseFunctions.instance;
      final result = await functions.httpsCallable('generateLiveKitToken').call({
        'alertId': alertId,
        'callId': call.id,
        'roomName': call.roomName,
      });

      final token = result.data['token'] as String;
      final serverUrl = result.data['serverUrl'] as String;

      debugPrint('[LiveKitService] Token received, connecting to: $serverUrl');

      // Create room instance
      _room = Room();
      await _room!.connect(
        serverUrl,
        token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      // Set up listeners
      _setupRoomListeners();

      // Publish local tracks
      await _publishLocalTracks(call.type);

      // Update call status to active
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .collection('calls')
          .doc(call.id)
          .update({
        'status': Call.STATUS_ACTIVE,
      });

      _currentCall = call.copyWith(status: Call.STATUS_ACTIVE);
      _callStateController.add(_currentCall);
      notifyListeners();

      debugPrint('[LiveKitService] Successfully joined room');
    } catch (e) {
      debugPrint('[LiveKitService] Error joining room: $e');
      rethrow;
    }
  }

  /// Publish local audio and video tracks
  Future<void> _publishLocalTracks(String callType) async {
    try {
      // Publish audio
      await _room?.localParticipant?.setMicrophoneEnabled(true);

      // Publish video only for video calls
      if (callType == Call.TYPE_VIDEO) {
        await _room?.localParticipant?.setCameraEnabled(true);
      }

      // Get local tracks
      _localAudioTrack = _room?.localParticipant?.audioTrackPublications.firstOrNull?.track as LocalAudioTrack?;
      _localVideoTrack = _room?.localParticipant?.videoTrackPublications.firstOrNull?.track as LocalVideoTrack?;

      notifyListeners();
    } catch (e) {
      debugPrint('[LiveKitService] Error publishing local tracks: $e');
    }
  }

  /// Set up room event listeners
  void _setupRoomListeners() {
    _room?.addListener(() {
      debugPrint('[LiveKitService] Room state changed: ${_room?.connectionState}');
      notifyListeners();
    });

    // Listen for remote participants
    final listener = _room?.createListener();

    listener?.on<ParticipantConnectedEvent>((event) {
      debugPrint('[LiveKitService] Participant connected: ${event.participant.identity}');
      notifyListeners();
    });

    listener?.on<ParticipantDisconnectedEvent>((event) {
      debugPrint('[LiveKitService] Participant disconnected: ${event.participant.identity}');
      notifyListeners();
    });

    listener?.on<TrackPublishedEvent>((event) {
      debugPrint('[LiveKitService] Track published: ${event.publication.sid}, kind: ${event.publication.kind}');
    });

    listener?.on<TrackSubscribedEvent>((event) {
      debugPrint('[LiveKitService] Track subscribed: ${event.track.sid}, kind: ${event.track.kind}');

      if (event.track is RemoteVideoTrack) {
        debugPrint('[LiveKitService] Setting remote video track');
        _remoteVideoTrack = event.track as RemoteVideoTrack;
      } else if (event.track is RemoteAudioTrack) {
        debugPrint('[LiveKitService] Setting remote audio track');
        _remoteAudioTrack = event.track as RemoteAudioTrack;
      }

      notifyListeners();
    });

    listener?.on<TrackUnsubscribedEvent>((event) {
      debugPrint('[LiveKitService] Track unsubscribed: ${event.track.sid}, kind: ${event.track.kind}');

      // Only clear if it's the current track
      if (event.track is RemoteVideoTrack && _remoteVideoTrack?.sid == event.track.sid) {
        debugPrint('[LiveKitService] Clearing remote video track');
        _remoteVideoTrack = null;
      } else if (event.track is RemoteAudioTrack && _remoteAudioTrack?.sid == event.track.sid) {
        debugPrint('[LiveKitService] Clearing remote audio track');
        _remoteAudioTrack = null;
      }

      notifyListeners();
    });

    listener?.on<RoomDisconnectedEvent>((event) {
      debugPrint('[LiveKitService] Room disconnected, reason: ${event.reason}');
      _handleRoomDisconnected();
    });

    listener?.on<RoomReconnectingEvent>((event) {
      debugPrint('[LiveKitService] Room reconnecting...');
      notifyListeners();
    });

    listener?.on<RoomReconnectedEvent>((event) {
      debugPrint('[LiveKitService] Room reconnected successfully');
      notifyListeners();
    });
  }

  /// Toggle microphone mute
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _room?.localParticipant?.setMicrophoneEnabled(!_isMuted);
    notifyListeners();
    debugPrint('[LiveKitService] Microphone ${_isMuted ? "muted" : "unmuted"}');
  }

  /// Toggle video on/off
  Future<void> toggleVideo() async {
    _isVideoEnabled = !_isVideoEnabled;
    await _room?.localParticipant?.setCameraEnabled(_isVideoEnabled);
    notifyListeners();
    debugPrint('[LiveKitService] Video ${_isVideoEnabled ? "enabled" : "disabled"}');
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    try {
      // Note: Camera switching API varies by platform
      // For web, camera switching needs to be handled differently
      // This is a placeholder for future implementation
      debugPrint('[LiveKitService] Camera switch requested (not fully implemented for web)');
      notifyListeners();
    } catch (e) {
      debugPrint('[LiveKitService] Error switching camera: $e');
    }
  }

  /// Toggle speaker/earpiece
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    // Note: Speaker control is handled by the device/browser
    // This is just a state tracker for UI purposes
    notifyListeners();
    debugPrint('[LiveKitService] Speaker ${_isSpeakerOn ? "on" : "off"}');
  }

  /// End the current call
  Future<void> endCall(String alertId, String callId) async {
    try {
      debugPrint('[LiveKitService] Ending call: $callId');

      final startTime = _currentCall?.startedAt;
      final answeredTime = _currentCall?.answeredAt;
      int? duration;

      if (startTime != null && answeredTime != null) {
        duration = DateTime.now().difference(answeredTime).inSeconds;
      }

      // Update call status in Firestore
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alertId)
          .collection('calls')
          .doc(callId)
          .update({
        'status': Call.STATUS_ENDED,
        'endedAt': FieldValue.serverTimestamp(),
        if (duration != null) 'duration': duration,
      });

      // Disconnect from room
      await _disconnectRoom();

      _currentCall = null;
      _callStateController.add(null);
      notifyListeners();

      debugPrint('[LiveKitService] Call ended successfully');
    } catch (e) {
      debugPrint('[LiveKitService] Error ending call: $e');
    }
  }

  /// Disconnect from LiveKit room
  Future<void> _disconnectRoom() async {
    try {
      debugPrint('[LiveKitService] Starting room disconnect...');

      // STEP 1: Disable camera and microphone at participant level FIRST
      // This is the most critical step to release media devices
      if (_room?.localParticipant != null) {
        debugPrint('[LiveKitService] Disabling camera and microphone at participant level');
        try {
          await _room?.localParticipant?.setCameraEnabled(false);
          debugPrint('[LiveKitService] Camera disabled');
        } catch (e) {
          debugPrint('[LiveKitService] Error disabling camera: $e');
        }

        try {
          await _room?.localParticipant?.setMicrophoneEnabled(false);
          debugPrint('[LiveKitService] Microphone disabled');
        } catch (e) {
          debugPrint('[LiveKitService] Error disabling microphone: $e');
        }

        // Give browser time to release media streams (PWA needs longer)
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // STEP 2: Stop and dispose local tracks
      if (_localVideoTrack != null) {
        debugPrint('[LiveKitService] Stopping local video track');
        try {
          await _localVideoTrack?.stop();
          await _localVideoTrack?.dispose();
        } catch (e) {
          debugPrint('[LiveKitService] Error stopping video track: $e');
        }
        _localVideoTrack = null;
      }

      if (_localAudioTrack != null) {
        debugPrint('[LiveKitService] Stopping local audio track');
        try {
          await _localAudioTrack?.stop();
          await _localAudioTrack?.dispose();
        } catch (e) {
          debugPrint('[LiveKitService] Error stopping audio track: $e');
        }
        _localAudioTrack = null;
      }

      // STEP 3: Clear remote tracks
      _remoteVideoTrack = null;
      _remoteAudioTrack = null;

      // STEP 4: Disconnect and dispose room
      if (_room != null) {
        debugPrint('[LiveKitService] Disconnecting from room');
        try {
          await _room?.disconnect();
          debugPrint('[LiveKitService] Disconnected from room');
        } catch (e) {
          debugPrint('[LiveKitService] Error disconnecting: $e');
        }

        // Extra delay before disposing (PWA-specific)
        await Future.delayed(const Duration(milliseconds: 100));

        debugPrint('[LiveKitService] Disposing room');
        try {
          await _room?.dispose();
          debugPrint('[LiveKitService] Room disposed');
        } catch (e) {
          debugPrint('[LiveKitService] Error disposing room: $e');
        }
        _room = null;
      }

      // STEP 5: NUCLEAR - Force stop all media tracks via JavaScript (PWA fix)
      if (kIsWeb) {
        debugPrint('[LiveKitService] PWA: Calling JavaScript to force stop ALL media tracks');
        try {
          // Call the global JavaScript function to stop all tracks
          await _callJavaScriptMediaCleanup();
        } catch (e) {
          debugPrint('[LiveKitService] PWA: JavaScript cleanup error (non-critical): $e');
        }
      }

      // Reset state
      _isMuted = false;
      _isVideoEnabled = true;
      _isSpeakerOn = true;

      notifyListeners();
      debugPrint('[LiveKitService]  Room disconnect complete - camera/mic released');
    } catch (e) {
      debugPrint('[LiveKitService] [ERROR] Fatal error during disconnect: $e');
      // Force cleanup even if error
      _room = null;
      _localVideoTrack = null;
      _localAudioTrack = null;
      _remoteVideoTrack = null;
      _remoteAudioTrack = null;
      notifyListeners();
    }
  }

  /// Handle room disconnection
  void _handleRoomDisconnected() {
    _disconnectRoom();
    _currentCall = null;
    _callStateController.add(null);
    notifyListeners();
  }

  /// Listen to call status updates from Firestore
  void _listenToCallUpdates(String alertId, String callId) {
    _callSubscription?.cancel();
    _callSubscription = FirebaseFirestore.instance
        .collection('emergency_alerts')
        .doc(alertId)
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final call = Call.fromFirestore(snapshot);
        _currentCall = call;
        _callStateController.add(call);
        notifyListeners();
      }
    });
  }

  /// Call JavaScript to force stop all media tracks (PWA-specific)
  Future<void> _callJavaScriptMediaCleanup() async {
    if (!kIsWeb) return;

    try {
      debugPrint('[LiveKitService] Calling window.forceStopAllMediaTracks()');
      final result = js.context.callMethod('forceStopAllMediaTracks', []);
      debugPrint('[LiveKitService] JavaScript cleanup result: $result');

      // Give browser time to process
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('[LiveKitService] Error calling JavaScript cleanup: $e');
    }
  }

  /// Clean up resources
  @override
  void dispose() {
    _callSubscription?.cancel();
    _disconnectRoom();
    _callStateController.close();
    super.dispose();
  }
}
