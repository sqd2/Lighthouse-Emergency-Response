import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medical_info.dart';
import 'encryption_service.dart';

/// Service for managing encrypted medical information
/// Handles CRUD operations with client-side encryption
class MedicalInfoService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _isInitialized = false;

  /// Initialize the medical info service
  static Future<void> initialize() async {
    if (_isInitialized) {
      print('⚠️ MedicalInfoService already initialized, skipping...');
      return;
    }

    try {
      print('=== Initializing MedicalInfoService ===');
      await EncryptionService.initialize();
      _isInitialized = true;
      print('✅ MedicalInfoService initialized successfully');
    } catch (e) {
      print('❌ Error initializing MedicalInfoService: $e');
      _isInitialized = false;
    }
  }

  /// Save medical info (encrypts before storing)
  static Future<void> saveMedicalInfo(MedicalInfo medicalInfo) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      print('=== Saving Medical Info ===');

      // Convert medical info to JSON
      final medicalDataJson = medicalInfo.toJson();

      // Encrypt the data
      final encrypted = EncryptionService.encryptMap(medicalDataJson, user.uid);

      // Store in Firestore with encryption metadata
      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medical_info')
          .doc('data');

      await docRef.set({
        'encryptedData': encrypted['encryptedData'],
        'iv': encrypted['iv'],
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Medical info saved successfully (encrypted)');
    } catch (e) {
      print('❌ Error saving medical info: $e');
      rethrow;
    }
  }

  /// Get medical info (decrypts after reading)
  static Future<MedicalInfo?> getMedicalInfo({String? forUserId}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Determine which user's medical info to fetch
      final targetUserId = forUserId ?? user.uid;

      print('=== Getting Medical Info for user: $targetUserId ===');

      final docRef = _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('medical_info')
          .doc('data');

      final doc = await docRef.get();

      if (!doc.exists) {
        print('⚠️ No medical info found');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        print('⚠️ Medical info document is empty');
        return null;
      }

      // Extract encrypted data and IV
      final encryptedData = data['encryptedData'] as String?;
      final iv = data['iv'] as String?;

      if (encryptedData == null || iv == null) {
        print('⚠️ Missing encrypted data or IV');
        return null;
      }

      // Decrypt the data using the target user's UID
      final decryptedMap = EncryptionService.decryptToMap(
        encryptedData,
        iv,
        targetUserId,
      );

      // Convert to MedicalInfo object
      final medicalInfo = MedicalInfo.fromJson(decryptedMap);

      print('✅ Medical info retrieved and decrypted successfully');

      // Log access for audit (if accessing another user's data)
      if (forUserId != null && forUserId != user.uid) {
        await _logAccess(targetUserId, user.uid);
      }

      return medicalInfo;
    } catch (e) {
      print('❌ Error getting medical info: $e');
      rethrow;
    }
  }

  /// Check if user has medical info stored
  static Future<bool> hasMedicalInfo({String? forUserId}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return false;
      }

      final targetUserId = forUserId ?? user.uid;

      final docRef = _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('medical_info')
          .doc('data');

      final doc = await docRef.get();
      return doc.exists;
    } catch (e) {
      print('❌ Error checking medical info: $e');
      return false;
    }
  }

  /// Delete medical info
  static Future<void> deleteMedicalInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      print('=== Deleting Medical Info ===');

      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medical_info')
          .doc('data');

      await docRef.delete();

      print('✅ Medical info deleted successfully');
    } catch (e) {
      print('❌ Error deleting medical info: $e');
      rethrow;
    }
  }

  /// Log when a dispatcher accesses medical info (for audit purposes)
  static Future<void> _logAccess(String medicalInfoOwnerId, String accessorId) async {
    try {
      final logRef = _firestore
          .collection('users')
          .doc(medicalInfoOwnerId)
          .collection('medical_info_access_log')
          .doc();

      await logRef.set({
        'accessedBy': accessorId,
        'accessedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Medical info access logged');
    } catch (e) {
      print('⚠️ Failed to log medical info access: $e');
      // Don't throw - logging failure shouldn't break the main operation
    }
  }

  /// Get encrypted medical info for sharing with dispatcher during SOS
  /// Returns raw encrypted data that can be included in emergency alert
  static Future<Map<String, dynamic>?> getEncryptedMedicalInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medical_info')
          .doc('data');

      final doc = await docRef.get();

      if (!doc.exists) {
        print('⚠️ No medical info to share');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        return null;
      }

      // Return the encrypted data along with the user ID needed for decryption
      return {
        'encryptedData': data['encryptedData'],
        'iv': data['iv'],
        'ownerId': user.uid, // Dispatcher needs this to decrypt
      };
    } catch (e) {
      print('❌ Error getting encrypted medical info: $e');
      return null;
    }
  }

  /// Decrypt medical info from emergency alert (for dispatchers)
  static Future<MedicalInfo?> decryptMedicalInfoFromAlert(
    Map<String, dynamic> encryptedMedicalData,
  ) async {
    try {
      final encryptedData = encryptedMedicalData['encryptedData'] as String?;
      final iv = encryptedMedicalData['iv'] as String?;
      final ownerId = encryptedMedicalData['ownerId'] as String?;

      if (encryptedData == null || iv == null || ownerId == null) {
        print('⚠️ Missing encryption data or owner ID');
        return null;
      }

      // Decrypt using the original owner's UID
      final decryptedMap = EncryptionService.decryptToMap(
        encryptedData,
        iv,
        ownerId,
      );

      final medicalInfo = MedicalInfo.fromJson(decryptedMap);

      print('✅ Medical info decrypted from alert');

      // Log access
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid != ownerId) {
        await _logAccess(ownerId, currentUser.uid);
      }

      return medicalInfo;
    } catch (e) {
      print('❌ Error decrypting medical info from alert: $e');
      rethrow;
    }
  }
}
