import 'package:flutter/material.dart';
import '../models/medical_info.dart';
import '../services/medical_info_service.dart';

class MedicalInfoDisplay extends StatefulWidget {
  final Map<String, dynamic>? encryptedMedicalData;

  const MedicalInfoDisplay({
    Key? key,
    required this.encryptedMedicalData,
  }) : super(key: key);

  @override
  State<MedicalInfoDisplay> createState() => _MedicalInfoDisplayState();
}

class _MedicalInfoDisplayState extends State<MedicalInfoDisplay> {
  MedicalInfo? _medicalInfo;
  bool _isLoading = false;
  bool _isExpanded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMedicalInfo();
  }

  Future<void> _loadMedicalInfo() async {
    if (widget.encryptedMedicalData == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final medicalInfo = await MedicalInfoService.decryptMedicalInfoFromAlert(
        widget.encryptedMedicalData!,
      );

      if (mounted) {
        setState(() {
          _medicalInfo = medicalInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error decrypting medical info: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to decrypt medical information';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildInfoChip(String label, {Color? color}) {
    return Chip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: color ?? Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color? iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? Colors.blue),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // No medical info provided
    if (widget.encryptedMedicalData == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey.shade600),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'No medical information provided',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Loading state
    if (_isLoading) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Decrypting medical information...'),
            ],
          ),
        ),
      );
    }

    // Error state
    if (_errorMessage != null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // No data after decryption
    if (_medicalInfo == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Column(
        children: [
          // Header with expand/collapse
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.medical_information,
                    color: Colors.red.shade700,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Medical Information Available',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Tap to view details',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Blood Type
                  if (_medicalInfo!.bloodType.isNotEmpty) ...[
                    _buildSection(
                      title: 'Blood Type',
                      icon: Icons.bloodtype,
                      iconColor: Colors.red,
                      children: [
                        _buildInfoChip(
                          _medicalInfo!.bloodType,
                          color: Colors.red.shade100,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Allergies (Critical - Red)
                  if (_medicalInfo!.allergies.isNotEmpty) ...[
                    _buildSection(
                      title: 'Allergies',
                      icon: Icons.warning,
                      iconColor: Colors.red.shade700,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _medicalInfo!.allergies
                              .map((allergy) => _buildInfoChip(
                                    allergy,
                                    color: Colors.red.shade100,
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Current Medications
                  if (_medicalInfo!.medications.isNotEmpty) ...[
                    _buildSection(
                      title: 'Current Medications',
                      icon: Icons.medication,
                      iconColor: Colors.orange,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _medicalInfo!.medications
                              .map((med) => _buildInfoChip(
                                    med,
                                    color: Colors.orange.shade100,
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Medical Conditions
                  if (_medicalInfo!.conditions.isNotEmpty) ...[
                    _buildSection(
                      title: 'Medical Conditions',
                      icon: Icons.local_hospital,
                      iconColor: Colors.blue,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _medicalInfo!.conditions
                              .map((condition) => _buildInfoChip(
                                    condition,
                                    color: Colors.blue.shade100,
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Emergency Contact
                  if (!_medicalInfo!.emergencyContact.isEmpty) ...[
                    _buildSection(
                      title: 'Emergency Contact',
                      icon: Icons.contact_phone,
                      iconColor: Colors.green,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_medicalInfo!.emergencyContact.name.isNotEmpty)
                                Text(
                                  _medicalInfo!.emergencyContact.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              if (_medicalInfo!.emergencyContact.relationship.isNotEmpty)
                                Text(
                                  _medicalInfo!.emergencyContact.relationship,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 14,
                                  ),
                                ),
                              if (_medicalInfo!.emergencyContact.phone.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.phone, size: 16, color: Colors.green.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      _medicalInfo!.emergencyContact.phone,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Additional Notes
                  if (_medicalInfo!.notes.isNotEmpty) ...[
                    _buildSection(
                      title: 'Additional Notes',
                      icon: Icons.note,
                      iconColor: Colors.purple,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _medicalInfo!.notes,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Privacy notice
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'This information is encrypted and access is logged for security.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
