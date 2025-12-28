/// Validation utilities for authentication and user input
class Validators {
  /// Email validation
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Password validation
  /// Must be at least 8 characters with:
  /// - At least one uppercase letter
  /// - At least one lowercase letter
  /// - At least one number
  /// - At least one special character
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 8) {
      return 'Password must be at least 8 characters long';
    }

    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }

    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }

    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }

    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character (!@#\$%^&*(),.?":{}|<>)';
    }

    return null;
  }

  /// Phone number validation for Malaysian format
  /// Expected format: +60123456789 or +60112345678
  static String? validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }

    final phone = value.trim();

    // Must start with +60
    if (!phone.startsWith('+60')) {
      return 'Phone number must start with +60';
    }

    // Remove +60 prefix for validation
    final numberPart = phone.substring(3);

    // Must be 9 or 10 digits (mobile numbers)
    if (numberPart.length < 9 || numberPart.length > 10) {
      return 'Invalid phone number length';
    }

    // Must contain only digits
    if (!RegExp(r'^\d+$').hasMatch(numberPart)) {
      return 'Phone number must contain only digits after +60';
    }

    // Valid Malaysian mobile prefixes (10, 11, 12, 13, 14, 15, 16, 17, 18, 19)
    final firstTwoDigits = numberPart.substring(0, 2);
    final validPrefixes = ['10', '11', '12', '13', '14', '15', '16', '17', '18', '19'];

    if (!validPrefixes.contains(firstTwoDigits)) {
      return 'Invalid Malaysian mobile number prefix';
    }

    return null;
  }

  /// Name validation
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }

    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters long';
    }

    return null;
  }

  /// Get detailed Firebase Auth error message
  static String getFirebaseAuthErrorMessage(String errorCode) {
    switch (errorCode) {
      // Login errors
      case 'user-not-found':
        return 'No account found with this email address. Please register first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again or use "Forgot Password".';
      case 'invalid-email':
        return 'Invalid email format. Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';

      // Registration errors
      case 'email-already-in-use':
        return 'An account with this email already exists. Please login instead.';
      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled. Please contact support.';

      // Network errors
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';

      // Password reset errors
      case 'expired-action-code':
        return 'This password reset link has expired. Please request a new one.';
      case 'invalid-action-code':
        return 'Invalid password reset link. Please request a new one.';

      // Default
      default:
        return 'Authentication error: $errorCode';
    }
  }
}
