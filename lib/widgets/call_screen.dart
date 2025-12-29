import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/call.dart';
import '../services/livekit_service.dart';
import '../main.dart' show setInCall;

/// Full-screen call interface with video/audio
class CallScreen extends StatefulWidget {
  final String alertId;
  final Call call;
  final bool isOutgoing;

  const CallScreen({
    super.key,
    required this.alertId,
    required this.call,
    required this.isOutgoing,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _liveKitService = LiveKitService();
  Timer? _durationTimer;
  int _callDuration = 0;
  bool _isConnected = false;
  bool _isJoining = false; // Prevent duplicate join attempts
  bool _isEndingCall = false; // Track if we're the one ending the call
  StreamSubscription? _callStateSubscription;
  StreamSubscription? _callDocSubscription; // Listen to call document changes
  String? _otherUserName; // Name of the other user in the call

  @override
  void initState() {
    super.initState();

    // Fetch other user's name
    _fetchOtherUserName();

    // Mark as in call to prevent incoming call dialogs
    setInCall(true);

    // Keep screen on during call
    WakelockPlus.enable();

    // Start call duration timer
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isConnected && mounted) {
        setState(() {
          _callDuration++;
        });
      }
    });

    // Listen to service changes
    _liveKitService.addListener(_onServiceUpdate);

    // Listen to call state changes
    _callStateSubscription = _liveKitService.callStateStream.listen((call) {
      if (call != null && mounted) {
        // If call is accepted/active and we haven't joined yet, join the room
        if ((call.status == Call.STATUS_ACTIVE || call.status == Call.STATUS_CONNECTING) &&
            _liveKitService.room == null && !_isJoining) {
          debugPrint('[CallScreen] Call state changed to ${call.status}, joining room');
          _joinRoom();
        }
        // If call is rejected by other party, close screen
        else if (call.status == Call.STATUS_REJECTED && !widget.isOutgoing) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Call was declined')),
            );
          }
        }
        // Note: Don't auto-pop on STATUS_ENDED - let endCall() handle navigation
      }
    });

    // Listen to call document changes to detect when other party ends the call
    _callDocSubscription = FirebaseFirestore.instance
        .collection('emergency_alerts')
        .doc(widget.alertId)
        .collection('calls')
        .doc(widget.call.id)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String?;
      final endedAt = data['endedAt'];

      debugPrint('[CallScreen] Call status changed to: $status, endedAt: $endedAt');

      // Only close if status is ended/rejected AND there's an endedAt timestamp
      // AND we're not the one who ended it (to prevent double pop)
      if ((status == Call.STATUS_ENDED || status == Call.STATUS_REJECTED) &&
          endedAt != null &&
          !_isEndingCall) {
        debugPrint('[CallScreen] Call ended by other party, closing screen');
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                status == Call.STATUS_REJECTED
                    ? 'Call was declined'
                    : 'Call ended',
              ),
            ),
          );
        }
      }
    });

    // If incoming call, join room immediately (receiver already accepted)
    if (!widget.isOutgoing) {
      _joinRoom();
    }
  }

  @override
  void dispose() {
    // Mark as not in call anymore
    setInCall(false);

    _durationTimer?.cancel();
    _callStateSubscription?.cancel();
    _callDocSubscription?.cancel();
    _liveKitService.removeListener(_onServiceUpdate);
    WakelockPlus.disable();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {
        final room = _liveKitService.room;
        _isConnected = room?.connectionState == livekit.ConnectionState.connected;
      });
    }
  }

  Future<void> _fetchOtherUserName() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        setState(() {
          _otherUserName = 'Unknown User';
        });
        return;
      }

      // Determine which name to show based on current user
      final isReceiver = currentUserId == widget.call.receiverId;
      final otherUserName = isReceiver
          ? widget.call.callerName
          : (widget.call.receiverName ?? 'Unknown User');

      debugPrint('[CallScreen] Current user: $currentUserId, Is receiver: $isReceiver, Other user name: $otherUserName');

      setState(() {
        _otherUserName = otherUserName;
      });
    } catch (e) {
      debugPrint('[CallScreen] Error determining other user name: $e');
      setState(() {
        _otherUserName = 'Unknown User';
      });
    }
  }

  Future<void> _joinRoom() async {
    // Prevent duplicate join attempts
    if (_isJoining || _liveKitService.room != null) {
      debugPrint('[CallScreen] Skipping join - already joining or connected');
      return;
    }

    debugPrint('[CallScreen] Starting room join process');
    _isJoining = true;

    try {
      await _liveKitService.joinRoom(widget.alertId, widget.call);
      if (mounted) {
        setState(() {
          _isConnected = true;
        });
      }
    } catch (e) {
      debugPrint('[CallScreen] Error joining room: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    } finally {
      _isJoining = false;
    }
  }

  Future<void> _endCall() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Call?'),
        content: const Text('Are you sure you want to end this call?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Call'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Set flag to prevent listener from also popping the navigator
      _isEndingCall = true;
      debugPrint('[CallScreen] User ending call, setting flag to prevent double pop');

      await _liveKitService.endCall(widget.alertId, widget.call.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final remoteVideoTrack = _liveKitService.remoteVideoTrack;
    final localVideoTrack = _liveKitService.localVideoTrack;
    final hasVideo = _liveKitService.isVideoEnabled || remoteVideoTrack != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video (full screen)
            if (remoteVideoTrack != null)
              Positioned.fill(
                child: livekit.VideoTrackRenderer(
                  remoteVideoTrack,
                ),
              )
            else
              // No video - show avatar/placeholder
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[800],
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _otherUserName ?? 'Connecting...',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isConnected
                        ? _formatDuration(_callDuration)
                        : (widget.isOutgoing ? 'Calling...' : 'Connecting...'),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),

            // Local video (picture-in-picture)
            if (localVideoTrack != null && _liveKitService.isVideoEnabled)
              Positioned(
                top: 16,
                right: 16,
                width: 120,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: livekit.VideoTrackRenderer(
                      localVideoTrack,
                    ),
                  ),
                ),
              ),

            // Top bar with participant name and duration
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _otherUserName ?? 'Connecting...',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isConnected
                        ? _formatDuration(_callDuration)
                        : (widget.isOutgoing ? 'Calling...' : 'Connecting...'),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute button
                    _CallControlButton(
                      icon: _liveKitService.isMuted ? Icons.mic_off : Icons.mic,
                      label: _liveKitService.isMuted ? 'Unmute' : 'Mute',
                      backgroundColor: _liveKitService.isMuted ? Colors.red : Colors.white.withOpacity(0.2),
                      onPressed: _liveKitService.toggleMute,
                    ),

                    // Video toggle (switch between audio and video mode)
                    _CallControlButton(
                      icon: _liveKitService.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                      label: _liveKitService.isVideoEnabled ? 'Audio Only' : 'Video',
                      backgroundColor: !_liveKitService.isVideoEnabled ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.2),
                      onPressed: _liveKitService.toggleVideo,
                    ),

                    // End call button
                    _CallControlButton(
                      icon: Icons.call_end,
                      label: 'End',
                      backgroundColor: Colors.red,
                      onPressed: _endCall,
                      isLarge: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Call control button widget
class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onPressed;
  final bool isLarge;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onPressed,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.all(isLarge ? 20.0 : 16.0),
              child: Icon(
                icon,
                color: Colors.white,
                size: isLarge ? 32 : 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

