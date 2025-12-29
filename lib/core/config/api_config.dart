import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central configuration for all API keys and external service endpoints.
/// This file consolidates API keys that are safe to be exposed in client-side code.
///
/// Note: API keys included here are client-side keys with domain restrictions.
/// Server-side secrets should be managed in Firebase Functions environment variables.
class ApiConfig {
  /// Private constructor to prevent instantiation of this utility class.
  ApiConfig._();

  /// Google Maps API key used for Places API, Directions API, and Maps JavaScript API.
  ///
  /// This key has restrictions configured in Google Cloud Console:
  /// - HTTP referrers restriction for web usage
  /// - API restrictions limiting to specific services (Places, Directions, Maps JavaScript)
  ///
  /// Security note: While this key is exposed in client code, it is protected by
  /// domain restrictions and API restrictions in the Google Cloud Console.
  static String get googleMapsApiKey =>
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? 'AIzaSyCvvz3UmQXQR9PzRUeYlNu2wJqpxG8FvuQ';

  /// LiveKit server URL for real-time communication.
  ///
  /// This URL points to the LiveKit server instance used for WebRTC connections.
  /// The actual authentication tokens are generated server-side via Cloud Functions.
  static String get liveKitUrl =>
      dotenv.env['LIVEKIT_URL'] ?? 'wss://lighthouse-u7fqfxnv.livekit.cloud';

  /// Validates that all required API keys are configured.
  ///
  /// Returns true if all required API keys have non-empty values.
  /// This method can be called during app initialization to verify configuration.
  static bool validateConfiguration() {
    return googleMapsApiKey.isNotEmpty && liveKitUrl.isNotEmpty;
  }

  /// Returns a map of all configured API endpoints for debugging purposes.
  ///
  /// Note: This method returns configuration keys, not the actual values,
  /// to prevent accidental logging of sensitive information.
  static Map<String, String> getConfigurationStatus() {
    return {
      'googleMapsApiKey': googleMapsApiKey.isNotEmpty ? 'Configured' : 'Missing',
      'liveKitUrl': liveKitUrl.isNotEmpty ? 'Configured' : 'Missing',
    };
  }
}
