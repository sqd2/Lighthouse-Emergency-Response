import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/utils/validators.dart';

void main() {
  group('Email Validator Tests', () {
    test('should accept valid email addresses', () {
      expect(Validators.validateEmail('user@example.com'), isNull);
      expect(Validators.validateEmail('test.user@domain.co.uk'), isNull);
      expect(Validators.validateEmail('name+tag@company.org'), isNull);
      expect(Validators.validateEmail('admin_123@test-site.com'), isNull);
    });

    test('should reject empty or null email', () {
      expect(Validators.validateEmail(null), 'Email is required');
      expect(Validators.validateEmail(''), 'Email is required');
      expect(Validators.validateEmail('   '), 'Email is required');
    });

    test('should reject invalid email formats', () {
      expect(Validators.validateEmail('notanemail'), contains('valid email'));
      expect(Validators.validateEmail('@example.com'), contains('valid email'));
      expect(Validators.validateEmail('user@'), contains('valid email'));
      expect(Validators.validateEmail('user @example.com'), contains('valid email'));
      expect(Validators.validateEmail('user@example'), contains('valid email'));
    });
  });

  group('Password Validator Tests', () {
    test('should accept valid passwords', () {
      expect(Validators.validatePassword('Test1234!'), isNull);
      expect(Validators.validatePassword('MyP@ssw0rd'), isNull);
      expect(Validators.validatePassword('Secure#Pass9'), isNull);
      expect(Validators.validatePassword('Valid123!Password'), isNull);
    });

    test('should reject empty or null password', () {
      expect(Validators.validatePassword(null), 'Password is required');
      expect(Validators.validatePassword(''), 'Password is required');
    });

    test('should reject password shorter than 8 characters', () {
      expect(
        Validators.validatePassword('Test1!'),
        contains('at least 8 characters'),
      );
    });

    test('should reject password without uppercase letter', () {
      expect(
        Validators.validatePassword('test1234!'),
        contains('uppercase letter'),
      );
    });

    test('should reject password without lowercase letter', () {
      expect(
        Validators.validatePassword('TEST1234!'),
        contains('lowercase letter'),
      );
    });

    test('should reject password without number', () {
      expect(
        Validators.validatePassword('TestPass!'),
        contains('one number'),
      );
    });

    test('should reject password without special character', () {
      expect(
        Validators.validatePassword('TestPass123'),
        contains('special character'),
      );
    });
  });

  group('Phone Number Validator Tests', () {
    test('should accept valid Malaysian phone numbers', () {
      expect(Validators.validatePhoneNumber('+60123456789'), isNull);
      expect(Validators.validatePhoneNumber('+60111234567'), isNull);
      expect(Validators.validatePhoneNumber('+60198765432'), isNull);
      expect(Validators.validatePhoneNumber('+60147654321'), isNull);
      expect(Validators.validatePhoneNumber('+60156789012'), isNull);
    });

    test('should reject empty or null phone number', () {
      expect(Validators.validatePhoneNumber(null), 'Phone number is required');
      expect(Validators.validatePhoneNumber(''), 'Phone number is required');
      expect(Validators.validatePhoneNumber('   '), 'Phone number is required');
    });

    test('should reject phone numbers without +60 prefix', () {
      expect(
        Validators.validatePhoneNumber('0123456789'),
        contains('must start with +60'),
      );
      expect(
        Validators.validatePhoneNumber('123456789'),
        contains('must start with +60'),
      );
      expect(
        Validators.validatePhoneNumber('+65123456789'),
        contains('must start with +60'),
      );
    });

    test('should reject phone numbers with invalid length', () {
      expect(
        Validators.validatePhoneNumber('+6012345'),
        contains('Invalid phone number length'),
      );
      expect(
        Validators.validatePhoneNumber('+6012345678901'),
        contains('Invalid phone number length'),
      );
    });

    test('should reject phone numbers with non-digits', () {
      // Use numbers with valid length (9-10 digits) but containing non-digits
      expect(
        Validators.validatePhoneNumber('+6012345678a'),
        contains('contain only digits'),
      );
      expect(
        Validators.validatePhoneNumber('+60123-45678'),
        contains('contain only digits'),
      );
    });

    test('should reject invalid Malaysian mobile prefixes', () {
      expect(
        Validators.validatePhoneNumber('+60023456789'),
        contains('Invalid Malaysian mobile number prefix'),
      );
      expect(
        Validators.validatePhoneNumber('+60523456789'),
        contains('Invalid Malaysian mobile number prefix'),
      );
      expect(
        Validators.validatePhoneNumber('+60993456789'),
        contains('Invalid Malaysian mobile number prefix'),
      );
    });
  });

  group('Name Validator Tests', () {
    test('should accept valid names', () {
      expect(Validators.validateName('John'), isNull);
      expect(Validators.validateName('Sarah Smith'), isNull);
      expect(Validators.validateName('Muhammad Abdullah'), isNull);
      expect(Validators.validateName('Lee Wei Ming'), isNull);
    });

    test('should reject empty or null name', () {
      expect(Validators.validateName(null), 'Name is required');
      expect(Validators.validateName(''), 'Name is required');
      expect(Validators.validateName('   '), 'Name is required');
    });

    test('should reject name shorter than 2 characters', () {
      expect(
        Validators.validateName('A'),
        contains('at least 2 characters'),
      );
    });
  });

  group('Firebase Auth Error Messages Tests', () {
    test('should return correct messages for login errors', () {
      expect(
        Validators.getFirebaseAuthErrorMessage('user-not-found'),
        contains('No account found'),
      );
      expect(
        Validators.getFirebaseAuthErrorMessage('wrong-password'),
        contains('Incorrect password'),
      );
      expect(
        Validators.getFirebaseAuthErrorMessage('invalid-email'),
        contains('Invalid email format'),
      );
      expect(
        Validators.getFirebaseAuthErrorMessage('user-disabled'),
        contains('account has been disabled'),
      );
      expect(
        Validators.getFirebaseAuthErrorMessage('too-many-requests'),
        contains('Too many failed attempts'),
      );
    });

    test('should return correct messages for registration errors', () {
      expect(
        Validators.getFirebaseAuthErrorMessage('email-already-in-use'),
        contains('already exists'),
      );
      expect(
        Validators.getFirebaseAuthErrorMessage('weak-password'),
        contains('too weak'),
      );
      expect(
        Validators.getFirebaseAuthErrorMessage('operation-not-allowed'),
        contains('not enabled'),
      );
    });

    test('should return correct messages for network errors', () {
      expect(
        Validators.getFirebaseAuthErrorMessage('network-request-failed'),
        contains('Network error'),
      );
    });

    test('should return correct messages for password reset errors', () {
      expect(
        Validators.getFirebaseAuthErrorMessage('expired-action-code'),
        contains('expired'),
      );
      expect(
        Validators.getFirebaseAuthErrorMessage('invalid-action-code'),
        contains('Invalid password reset link'),
      );
    });

    test('should return default message for unknown error codes', () {
      expect(
        Validators.getFirebaseAuthErrorMessage('unknown-error'),
        contains('Authentication error: unknown-error'),
      );
    });
  });
}
