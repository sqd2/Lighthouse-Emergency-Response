import 'package:flutter_test/flutter_test.dart';
import 'package:lighthouse/models/medical_info.dart';

void main() {
  group('MedicalInfo Model Tests', () {
    test('should create MedicalInfo instance with all fields', () {
      final medicalInfo = MedicalInfo(
        bloodType: 'O+',
        allergies: ['Penicillin', 'Peanuts'],
        medications: ['Aspirin'],
        conditions: ['Diabetes'],
        emergencyContact: EmergencyContact(
          name: 'John Doe',
          phone: '+60123456789',
          email: 'john@example.com',
          relationship: 'Spouse',
        ),
        notes: 'Type 2 diabetes, regular checkups',
      );

      expect(medicalInfo.bloodType, 'O+');
      expect(medicalInfo.allergies, ['Penicillin', 'Peanuts']);
      expect(medicalInfo.medications, ['Aspirin']);
      expect(medicalInfo.conditions, ['Diabetes']);
      expect(medicalInfo.emergencyContact.name, 'John Doe');
      expect(medicalInfo.emergencyContact.phone, '+60123456789');
      expect(medicalInfo.notes, 'Type 2 diabetes, regular checkups');
    });

    test('should serialize to JSON correctly', () {
      final medicalInfo = MedicalInfo(
        bloodType: 'A+',
        allergies: ['Latex'],
        medications: ['Insulin'],
        conditions: ['Asthma'],
        emergencyContact: EmergencyContact(
          name: 'Jane Smith',
          phone: '+60198765432',
          email: 'jane@example.com',
          relationship: 'Parent',
        ),
        notes: 'Carries inhaler',
      );

      final json = medicalInfo.toJson();

      expect(json['bloodType'], 'A+');
      expect(json['allergies'], ['Latex']);
      expect(json['medications'], ['Insulin']);
      expect(json['conditions'], ['Asthma']);
      expect(json['emergencyContact']['name'], 'Jane Smith');
      expect(json['emergencyContact']['phone'], '+60198765432');
      expect(json['notes'], 'Carries inhaler');
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'bloodType': 'B-',
        'allergies': ['Shellfish', 'Dust'],
        'medications': ['Antihistamine'],
        'conditions': ['Hypertension'],
        'emergencyContact': {
          'name': 'Bob Johnson',
          'phone': '+60111222333',
          'email': 'bob@example.com',
          'relationship': 'Sibling',
        },
        'notes': 'Monitor blood pressure',
      };

      final medicalInfo = MedicalInfo.fromJson(json);

      expect(medicalInfo.bloodType, 'B-');
      expect(medicalInfo.allergies, ['Shellfish', 'Dust']);
      expect(medicalInfo.medications, ['Antihistamine']);
      expect(medicalInfo.conditions, ['Hypertension']);
      expect(medicalInfo.emergencyContact.name, 'Bob Johnson');
      expect(medicalInfo.emergencyContact.phone, '+60111222333');
      expect(medicalInfo.notes, 'Monitor blood pressure');
    });

    test('should handle empty lists correctly', () {
      final medicalInfo = MedicalInfo(
        bloodType: 'AB+',
        allergies: [],
        medications: [],
        conditions: [],
        emergencyContact: EmergencyContact(
          name: 'No Contact',
          phone: '',
          email: '',
          relationship: '',
        ),
        notes: '',
      );

      expect(medicalInfo.allergies, isEmpty);
      expect(medicalInfo.medications, isEmpty);
      expect(medicalInfo.conditions, isEmpty);
      expect(medicalInfo.emergencyContact.phone, isEmpty);
      expect(medicalInfo.notes, isEmpty);
    });

    test('should handle serialization round-trip correctly', () {
      final original = MedicalInfo(
        bloodType: 'O-',
        allergies: ['Eggs', 'Milk'],
        medications: ['Vitamin D', 'Calcium'],
        conditions: ['Osteoporosis'],
        emergencyContact: EmergencyContact(
          name: 'Sarah Williams',
          phone: '+60123456780',
          email: 'sarah@example.com',
          relationship: 'Friend',
        ),
        notes: 'Bone density issues',
      );

      final json = original.toJson();
      final restored = MedicalInfo.fromJson(json);

      expect(restored.bloodType, original.bloodType);
      expect(restored.allergies, original.allergies);
      expect(restored.medications, original.medications);
      expect(restored.conditions, original.conditions);
      expect(restored.emergencyContact.name, original.emergencyContact.name);
      expect(restored.emergencyContact.phone, original.emergencyContact.phone);
      expect(restored.notes, original.notes);
    });

    test('should handle copyWith correctly', () {
      final original = MedicalInfo(
        bloodType: 'A-',
        allergies: ['Pollen'],
        medications: [],
        conditions: [],
        emergencyContact: EmergencyContact(
          name: 'Alice Brown',
          phone: '+60199887766',
          email: 'alice@example.com',
          relationship: 'Spouse',
        ),
        notes: 'Seasonal allergies',
      );

      final updated = original.copyWith(
        medications: ['Antihistamine'],
        notes: 'Updated notes',
      );

      // Changed fields
      expect(updated.medications, ['Antihistamine']);
      expect(updated.notes, 'Updated notes');

      // Unchanged fields
      expect(updated.bloodType, original.bloodType);
      expect(updated.allergies, original.allergies);
      expect(updated.emergencyContact.name, original.emergencyContact.name);
    });

    test('should check isEmpty correctly', () {
      final emptyInfo = MedicalInfo.empty();

      final nonEmptyInfo = MedicalInfo(
        bloodType: 'O+',
        allergies: [],
        medications: [],
        conditions: [],
        emergencyContact: EmergencyContact(
          name: '',
          phone: '',
          email: '',
          relationship: '',
        ),
        notes: '',
      );

      expect(emptyInfo.isEmpty, isTrue);
      expect(nonEmptyInfo.isEmpty, isFalse);
    });

    test('should check hasCriticalInfo correctly', () {
      final noCriticalInfo = MedicalInfo.empty();

      final hasAllergies = MedicalInfo(
        bloodType: '',
        allergies: ['Penicillin'],
        medications: [],
        conditions: [],
        emergencyContact: EmergencyContact(
          name: '',
          phone: '',
          email: '',
          relationship: '',
        ),
        notes: '',
      );

      final hasMedications = MedicalInfo(
        bloodType: '',
        allergies: [],
        medications: ['Insulin'],
        conditions: [],
        emergencyContact: EmergencyContact(
          name: '',
          phone: '',
          email: '',
          relationship: '',
        ),
        notes: '',
      );

      final hasConditions = MedicalInfo(
        bloodType: '',
        allergies: [],
        medications: [],
        conditions: ['Diabetes'],
        emergencyContact: EmergencyContact(
          name: '',
          phone: '',
          email: '',
          relationship: '',
        ),
        notes: '',
      );

      expect(noCriticalInfo.hasCriticalInfo, isFalse);
      expect(hasAllergies.hasCriticalInfo, isTrue);
      expect(hasMedications.hasCriticalInfo, isTrue);
      expect(hasConditions.hasCriticalInfo, isTrue);
    });
  });
}
