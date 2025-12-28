import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:otp/otp.dart';

/// Service for handling two-factor authentication
class TwoFactorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Generate a random 6-digit verification code
  String generateVerificationCode() {
    final random = Random.secure();
    final code = random.nextInt(900000) + 100000; // 100000-999999
    return code.toString();
  }

  /// Generate a random secret for TOTP (32 characters, base32)
  String generateTOTPSecret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; // Base32 alphabet
    final random = Random.secure();
    return List.generate(32, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// Generate TOTP code from secret (6 digits, 30 second window)
  String generateTOTPCode(String secret) {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    return OTP.generateTOTPCodeString(
      secret,
      currentTime,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
  }

  /// Verify TOTP code (allows 1 time window before/after for clock skew)
  bool verifyTOTPCode(String secret, String code) {
    final currentTime = DateTime.now().millisecondsSinceEpoch;

    // Check current window
    final currentCode = OTP.generateTOTPCodeString(
      secret,
      currentTime,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
    if (currentCode == code) return true;

    // Check previous window (30s ago)
    final previousCode = OTP.generateTOTPCodeString(
      secret,
      currentTime - 30000,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
    if (previousCode == code) return true;

    // Check next window (30s ahead)
    final nextCode = OTP.generateTOTPCodeString(
      secret,
      currentTime + 30000,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
    if (nextCode == code) return true;

    return false;
  }

  /// Send verification code via email
  Future<void> sendEmailVerificationCode(String email, String code) async {
    try {
      final callable = _functions.httpsCallable('sendEmail');
      await callable.call({
        'to': email,
        'subject': 'Lighthouse Emergency - 2FA Verification Code',
        'text': 'Your verification code is: $code\n\nThis code will expire in 10 minutes.\n\nIf you did not request this code, please ignore this email.',
        'html': '''
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #1976d2;">Lighthouse Emergency</h2>
            <p>Your two-factor authentication verification code is:</p>
            <div style="background-color: #f5f5f5; padding: 20px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 8px; margin: 20px 0;">
              $code
            </div>
            <p>This code will expire in 10 minutes.</p>
            <p style="color: #666; font-size: 14px;">If you did not request this code, please ignore this email.</p>
          </div>
        ''',
      });
    } catch (e) {
      throw Exception('Failed to send email verification code: $e');
    }
  }

  /// Send verification code via SMS
  Future<void> sendSMSVerificationCode(String phoneNumber, String code) async {
    try {
      final callable = _functions.httpsCallable('sendSMS');
      await callable.call({
        'to': phoneNumber,
        'message': 'Lighthouse Emergency: Your 2FA verification code is $code. Valid for 10 minutes.',
      });
    } catch (e) {
      throw Exception('Failed to send SMS verification code: $e');
    }
  }

  /// Store verification code in Firestore with expiration
  Future<void> storeVerificationCode(String userId, String code, String method) async {
    await _firestore.collection('verificationCodes').doc(userId).set({
      'code': code,
      'method': method, // 'email' or 'sms'
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 10))),
      'used': false,
    });
  }

  /// Verify stored verification code
  Future<bool> verifyStoredCode(String userId, String code) async {
    try {
      final doc = await _firestore.collection('verificationCodes').doc(userId).get();

      if (!doc.exists) return false;

      final data = doc.data()!;
      final storedCode = data['code'] as String;
      final expiresAt = (data['expiresAt'] as Timestamp).toDate();
      final used = data['used'] as bool;

      // Check if code matches, not expired, and not used
      if (storedCode == code && !used && DateTime.now().isBefore(expiresAt)) {
        // Mark as used
        await doc.reference.update({'used': true});
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get user's 2FA settings
  Future<Map<String, dynamic>?> get2FASettings(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      return {
        'twoFactorEnabled': data['twoFactorEnabled'] ?? false,
        'twoFactorMethod': data['twoFactorMethod'] ?? 'none', // 'email', 'sms', 'totp', 'none'
        'totpSecret': data['totpSecret'], // Only present if method is 'totp'
      };
    } catch (e) {
      return null;
    }
  }

  /// Enable 2FA for user
  Future<void> enable2FA(String userId, String method, {String? totpSecret}) async {
    final updateData = {
      'twoFactorEnabled': true,
      'twoFactorMethod': method,
    };

    if (method == 'totp' && totpSecret != null) {
      updateData['totpSecret'] = totpSecret;
    }

    await _firestore.collection('users').doc(userId).update(updateData);
  }

  /// Disable 2FA for user
  Future<void> disable2FA(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'twoFactorEnabled': false,
      'twoFactorMethod': 'none',
      'totpSecret': FieldValue.delete(),
    });
  }

  /// Generate otpauth URL for QR code (for authenticator apps)
  String generateOTPAuthURL(String email, String secret) {
    return 'otpauth://totp/Lighthouse Emergency:$email?secret=$secret&issuer=Lighthouse Emergency&algorithm=SHA1&digits=6&period=30';
  }
}
