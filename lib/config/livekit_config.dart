/// Configuration for LiveKit WebRTC integration
class LiveKitConfig {
  // LiveKit server URL - using LiveKit Cloud (free tier)
  // For self-hosted: Change to your own server URL (e.g., 'wss://your-server.com')
  static const String serverUrl = 'wss://lighthouse-webrtc-a5tfjg76.livekit.cloud';

  // Note: LiveKit tokens are generated server-side via Firebase Cloud Function
  // This ensures API keys/secrets are never exposed in client code

  // Timeout for incoming call ringing (30 seconds)
  static const Duration incomingCallTimeout = Duration(seconds: 30);

  // Maximum call duration (2 hours for emergency calls)
  static const Duration maxCallDuration = Duration(hours: 2);

  // Video quality settings
  static const int defaultVideoWidth = 1280;
  static const int defaultVideoHeight = 720;
  static const int defaultVideoFrameRate = 30;

  // Audio settings
  static const bool echoCancellation = true;
  static const bool noiseSuppression = true;
  static const bool autoGainControl = true;

  // Connection settings
  static const int reconnectAttempts = 3;
  static const Duration reconnectDelay = Duration(seconds: 2);

  // STUN server (Google's free STUN server as fallback)
  static const String stunServer = 'stun:stun.l.google.com:19302';

  // Note: TURN server configuration is handled by LiveKit Cloud
  // For self-hosted, you would configure TURN servers in LiveKit server config
}
