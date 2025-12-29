/// Service to manage 2FA verification state during login
class TwoFactorGate {
  static bool _isVerifying = false;

  /// Check if 2FA verification is currently in progress
  static bool get isVerifying => _isVerifying;

  /// Set 2FA verification state
  static void setVerifying(bool value) {
    _isVerifying = value;
  }

  /// Clear verification state (call on logout)
  static void reset() {
    _isVerifying = false;
  }
}
