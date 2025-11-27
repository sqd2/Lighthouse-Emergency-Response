/// Stub for non-web platforms
class FCMWeb {
  static Future<String?> getToken(String vapidKey) async {
    throw UnsupportedError('FCMWeb is only supported on web platform');
  }
}
