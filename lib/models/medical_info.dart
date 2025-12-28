import 'dart:convert';

/// Emergency contact information
class EmergencyContact {
  final String name;
  final String phone;
  final String email;
  final String relationship;

  EmergencyContact({
    required this.name,
    required this.phone,
    this.email = '',
    required this.relationship,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'relationship': relationship,
    };
  }

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
    );
  }

  bool get isEmpty => name.isEmpty && phone.isEmpty && email.isEmpty && relationship.isEmpty;
}

/// Medical information for a citizen user
/// This data is encrypted before storage in Firestore
class MedicalInfo {
  final String bloodType;
  final List<String> allergies;
  final List<String> medications;
  final List<String> conditions;
  final EmergencyContact emergencyContact;
  final String notes;

  MedicalInfo({
    this.bloodType = '',
    this.allergies = const [],
    this.medications = const [],
    this.conditions = const [],
    required this.emergencyContact,
    this.notes = '',
  });

  /// Convert to JSON (before encryption)
  Map<String, dynamic> toJson() {
    return {
      'bloodType': bloodType,
      'allergies': allergies,
      'medications': medications,
      'conditions': conditions,
      'emergencyContact': emergencyContact.toJson(),
      'notes': notes,
    };
  }

  /// Create from JSON (after decryption)
  factory MedicalInfo.fromJson(Map<String, dynamic> json) {
    return MedicalInfo(
      bloodType: json['bloodType'] as String? ?? '',
      allergies: (json['allergies'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      medications: (json['medications'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      conditions: (json['conditions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      emergencyContact: json['emergencyContact'] != null
          ? EmergencyContact.fromJson(
              json['emergencyContact'] as Map<String, dynamic>)
          : EmergencyContact(name: '', phone: '', email: '', relationship: ''),
      notes: json['notes'] as String? ?? '',
    );
  }

  /// Create an empty medical info object
  factory MedicalInfo.empty() {
    return MedicalInfo(
      bloodType: '',
      allergies: [],
      medications: [],
      conditions: [],
      emergencyContact: EmergencyContact(name: '', phone: '', email: '', relationship: ''),
      notes: '',
    );
  }

  /// Check if medical info is empty (no data filled)
  bool get isEmpty {
    return bloodType.isEmpty &&
        allergies.isEmpty &&
        medications.isEmpty &&
        conditions.isEmpty &&
        emergencyContact.isEmpty &&
        notes.isEmpty;
  }

  /// Check if medical info has any critical data (allergies, conditions, medications)
  bool get hasCriticalInfo {
    return allergies.isNotEmpty ||
        medications.isNotEmpty ||
        conditions.isNotEmpty;
  }

  /// Create a copy with updated fields
  MedicalInfo copyWith({
    String? bloodType,
    List<String>? allergies,
    List<String>? medications,
    List<String>? conditions,
    EmergencyContact? emergencyContact,
    String? notes,
  }) {
    return MedicalInfo(
      bloodType: bloodType ?? this.bloodType,
      allergies: allergies ?? this.allergies,
      medications: medications ?? this.medications,
      conditions: conditions ?? this.conditions,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() {
    return 'MedicalInfo(bloodType: $bloodType, allergies: ${allergies.length}, '
        'medications: ${medications.length}, conditions: ${conditions.length}, '
        'emergencyContact: ${emergencyContact.name}, notes: ${notes.isNotEmpty})';
  }
}
