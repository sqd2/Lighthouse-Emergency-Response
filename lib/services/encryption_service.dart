import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

/// Service for encrypting and decrypting medical data
/// Uses AES-256 encryption with user-specific keys derived from UID
class EncryptionService {
  static bool _isInitialized = false;
  static final Map<String, encrypt_lib.Key> _keyCache = {};

  /// Initialize the encryption service
  static Future<void> initialize() async {
    if (_isInitialized) {
      print('[WARN] EncryptionService already initialized, skipping...');
      return;
    }

    try {
      print('=== Initializing EncryptionService ===');
      _isInitialized = true;
      print(' EncryptionService initialized successfully');
    } catch (e) {
      print('[ERROR] Error initializing EncryptionService: $e');
      _isInitialized = false;
    }
  }

  /// Derive a secure encryption key from user UID
  /// Uses SHA-256 to create a consistent 32-byte key
  static encrypt_lib.Key _deriveKeyFromUID(String userUID) {
    // Check cache first
    if (_keyCache.containsKey(userUID)) {
      return _keyCache[userUID]!;
    }

    try {
      // Use SHA-256 to derive a 32-byte key from the UID
      // This creates a consistent key for the same user
      final bytes = utf8.encode(userUID);
      final digest = sha256.convert(bytes);
      final key = encrypt_lib.Key(Uint8List.fromList(digest.bytes));

      // Cache the key for performance
      _keyCache[userUID] = key;

      print(' Derived encryption key for user');
      return key;
    } catch (e) {
      print('[ERROR] Error deriving encryption key: $e');
      rethrow;
    }
  }

  /// Encrypt sensitive data
  /// Returns a map with encrypted data (base64) and IV (base64)
  static Map<String, String> encrypt(String plainText, String userUID) {
    try {
      if (plainText.isEmpty) {
        print('[WARN] Empty plaintext provided for encryption');
        return {'encryptedData': '', 'iv': ''};
      }

      // Derive key from user UID
      final key = _deriveKeyFromUID(userUID);

      // Generate a random IV (Initialization Vector) for this encryption
      final iv = encrypt_lib.IV.fromSecureRandom(16);

      // Create encrypter with AES algorithm
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );

      // Encrypt the data
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      print(' Data encrypted successfully');

      // Return both encrypted data and IV (both base64 encoded)
      return {'encryptedData': encrypted.base64, 'iv': iv.base64};
    } catch (e) {
      print('[ERROR] Error encrypting data: $e');
      rethrow;
    }
  }

  /// Decrypt encrypted data
  /// Requires the encrypted data (base64) and IV (base64)
  static String decrypt(
    String encryptedDataBase64,
    String ivBase64,
    String userUID,
  ) {
    try {
      if (encryptedDataBase64.isEmpty || ivBase64.isEmpty) {
        print('[WARN] Empty encrypted data or IV provided for decryption');
        return '';
      }

      // Derive the same key from user UID
      final key = _deriveKeyFromUID(userUID);

      // Recreate the IV from base64
      final iv = encrypt_lib.IV.fromBase64(ivBase64);

      // Create encrypter with the same AES configuration
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );

      // Decrypt the data
      final decrypted = encrypter.decrypt64(encryptedDataBase64, iv: iv);

      print(' Data decrypted successfully');
      return decrypted;
    } catch (e) {
      print('[ERROR] Error decrypting data: $e');
      print('   This may indicate corrupted data or wrong decryption key');
      rethrow;
    }
  }

  /// Encrypt a map of data (converts to JSON first)
  static Map<String, String> encryptMap(
    Map<String, dynamic> data,
    String userUID,
  ) {
    try {
      final jsonString = jsonEncode(data);
      return encrypt(jsonString, userUID);
    } catch (e) {
      print('[ERROR] Error encrypting map: $e');
      rethrow;
    }
  }

  /// Decrypt to a map (decrypts and parses JSON)
  static Map<String, dynamic> decryptToMap(
    String encryptedDataBase64,
    String ivBase64,
    String userUID,
  ) {
    try {
      final decrypted = decrypt(encryptedDataBase64, ivBase64, userUID);
      if (decrypted.isEmpty) {
        return {};
      }
      return jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (e) {
      print('[ERROR] Error decrypting to map: $e');
      rethrow;
    }
  }

  /// Clear the key cache (useful for logout or user switching)
  static void clearKeyCache() {
    _keyCache.clear();
    print(' Encryption key cache cleared');
  }

  /// Clear a specific user's key from cache
  static void clearUserKey(String userUID) {
    _keyCache.remove(userUID);
    print(' Encryption key cleared for user');
  }
}
