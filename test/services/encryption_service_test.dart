import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/services/encryption_service.dart';

void main() {
  group('Encryption Service Tests', () {
    setUpAll(() async {
      // ENC_001: Test service initialization
      await EncryptionService.initialize();
    });

    // ENC_003: Test key derivation consistency (indirect test via encryption)
    test('should derive consistent key from UID', () {
      final uid = 'user-123';
      final data = {'test': 'value'};

      // Same UID should produce same encryption key (same input = same output)
      final encrypted1 = EncryptionService.encryptMap(data, uid);
      final encrypted2 = EncryptionService.encryptMap(data, uid);

      // Encrypted data will be different (different IVs), but both should decrypt correctly
      final decrypted1 = EncryptionService.decryptToMap(
        encrypted1['encryptedData']!,
        encrypted1['iv']!,
        uid,
      );
      final decrypted2 = EncryptionService.decryptToMap(
        encrypted2['encryptedData']!,
        encrypted2['iv']!,
        uid,
      );

      expect(decrypted1, equals(data));
      expect(decrypted2, equals(data));
    });

    // ENC_005: Test encryption with valid data
    test('should encrypt data successfully', () {
      final uid = 'test-user-123';
      final data = {
        'name': 'John Doe',
        'bloodType': 'O+',
        'allergies': ['Penicillin'],
      };

      final encrypted = EncryptionService.encryptMap(data, uid);

      expect(encrypted, isNotNull);
      expect(encrypted['iv'], isNotNull);
      expect(encrypted['encryptedData'], isNotNull);
      expect(encrypted['encryptedData'], isNot(equals(data.toString())));
    });

    // ENC_006: Test decryption with valid encrypted data
    test('should decrypt data successfully', () {
      final uid = 'test-user-456';
      final originalData = {
        'name': 'Jane Smith',
        'bloodType': 'A+',
        'medications': ['Aspirin', 'Insulin'],
      };

      final encrypted = EncryptionService.encryptMap(originalData, uid);
      final decrypted = EncryptionService.decryptToMap(
        encrypted['encryptedData']!,
        encrypted['iv']!,
        uid,
      );

      expect(decrypted, equals(originalData));
    });

    // ENC_007: Test round-trip encryption/decryption
    test('should handle round-trip encryption/decryption', () {
      final uid = 'round-trip-user';
      final testCases = [
        {'simple': 'value'},
        {'complex': {'nested': {'data': 'here'}}},
        {'array': ['item1', 'item2', 'item3']},
        {'mixed': {'text': 'hello', 'number': 42, 'bool': true}},
      ];

      for (final data in testCases) {
        final encrypted = EncryptionService.encryptMap(data, uid);
        final decrypted = EncryptionService.decryptToMap(
          encrypted['encryptedData']!,
          encrypted['iv']!,
          uid,
        );

        expect(decrypted, equals(data),
            reason: 'Failed for data: $data');
      }
    });

    // ENC_008: Test decryption with wrong UID fails
    test('should fail to decrypt with wrong UID', () {
      final uid1 = 'user-correct';
      final uid2 = 'user-wrong';
      final data = {'secret': 'information'};

      final encrypted = EncryptionService.encryptMap(data, uid1);

      expect(
        () => EncryptionService.decryptToMap(
          encrypted['encryptedData']!,
          encrypted['iv']!,
          uid2,
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'Should throw ArgumentError when decrypting with wrong UID',
      );
    });

    // ENC_009: Test encryption with empty data
    test('should handle empty data', () {
      final uid = 'empty-data-user';
      final emptyData = <String, dynamic>{};

      final encrypted = EncryptionService.encryptMap(emptyData, uid);
      final decrypted = EncryptionService.decryptToMap(
        encrypted['encryptedData']!,
        encrypted['iv']!,
        uid,
      );

      expect(decrypted, equals(emptyData));
    });

    // ENC_010: Test encryption with special characters
    test('should handle special characters', () {
      final uid = 'special-char-user';
      final data = {
        'text': 'Special chars: !@#\$%^&*()_+-={}[]|:;<>,.?/~`',
        'unicode': '你好世界 🌍 مرحبا',
      };

      final encrypted = EncryptionService.encryptMap(data, uid);
      final decrypted = EncryptionService.decryptToMap(
        encrypted['encryptedData']!,
        encrypted['iv']!,
        uid,
      );

      expect(decrypted, equals(data));
    });

    // ENC_011: Test encryption with large data
    test('should handle large data', () {
      final uid = 'large-data-user';
      final largeText = 'Lorem ipsum ' * 1000; // ~12KB
      final data = {
        'large': largeText,
        'nested': {'more': largeText},
      };

      final encrypted = EncryptionService.encryptMap(data, uid);
      final decrypted = EncryptionService.decryptToMap(
        encrypted['encryptedData']!,
        encrypted['iv']!,
        uid,
      );

      expect(decrypted, equals(data));
    });
  });
}
