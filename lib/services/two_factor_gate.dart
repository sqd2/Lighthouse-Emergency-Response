import 'package:flutter/foundation.dart';

/// Service to manage 2FA verification state during login
class TwoFactorGate {
  static final ValueNotifier<bool> _isVerifyingNotifier = ValueNotifier(false);

  /// Get the notifier for reactive listening
  static ValueNotifier<bool> get notifier => _isVerifyingNotifier;

  /// Check if 2FA verification is currently in progress
  static bool get isVerifying => _isVerifyingNotifier.value;

  /// Set 2FA verification state
  static void setVerifying(bool value) {
    debugPrint('[TwoFactorGate] Setting isVerifying to: $value');
    _isVerifyingNotifier.value = value;
  }

  /// Clear verification state (call on logout)
  static void reset() {
    debugPrint('[TwoFactorGate] Resetting');
    _isVerifyingNotifier.value = false;
  }
}
