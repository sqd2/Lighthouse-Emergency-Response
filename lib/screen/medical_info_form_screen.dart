import 'package:flutter/material.dart';
import '../models/medical_info.dart';
import '../services/medical_info_service.dart';

class MedicalInfoFormScreen extends StatefulWidget {
  final MedicalInfo? existingInfo;

  const MedicalInfoFormScreen({Key? key, this.existingInfo}) : super(key: key);

  @override
  State<MedicalInfoFormScreen> createState() => _MedicalInfoFormScreenState();
}

class _MedicalInfoFormScreenState extends State<MedicalInfoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Form fields
  String _bloodType = '';
  final List<String> _allergies = [];
  final List<String> _medications = [];
  final List<String> _conditions = [];
  final TextEditingController _emergencyNameController = TextEditingController();
  final TextEditingController _emergencyPhoneController = TextEditingController();
  final TextEditingController _emergencyEmailController = TextEditingController();
  final TextEditingController _emergencyRelationshipController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // Controllers for chip inputs
  final TextEditingController _allergyController = TextEditingController();
  final TextEditingController _medicationController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController();

  // Blood type options
  final List<String> _bloodTypes = [
    '',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  void _loadExistingData() {
    if (widget.existingInfo != null) {
      setState(() {
        _bloodType = widget.existingInfo!.bloodType;
        _allergies.addAll(widget.existingInfo!.allergies);
        _medications.addAll(widget.existingInfo!.medications);
        _conditions.addAll(widget.existingInfo!.conditions);
        _emergencyNameController.text = widget.existingInfo!.emergencyContact.name;
        _emergencyPhoneController.text = widget.existingInfo!.emergencyContact.phone;
        _emergencyEmailController.text = widget.existingInfo!.emergencyContact.email;
        _emergencyRelationshipController.text = widget.existingInfo!.emergencyContact.relationship;
        _notesController.text = widget.existingInfo!.notes;
      });
    }
  }

  @override
  void dispose() {
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyEmailController.dispose();
    _emergencyRelationshipController.dispose();
    _notesController.dispose();
    _allergyController.dispose();
    _medicationController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  Future<void> _saveMedicalInfo() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final medicalInfo = MedicalInfo(
        bloodType: _bloodType,
        allergies: _allergies,
        medications: _medications,
        conditions: _conditions,
        emergencyContact: EmergencyContact(
          name: _emergencyNameController.text.trim(),
          phone: _emergencyPhoneController.text.trim(),
          email: _emergencyEmailController.text.trim(),
          relationship: _emergencyRelationshipController.text.trim(),
        ),
        notes: _notesController.text.trim(),
      );

      await MedicalInfoService.saveMedicalInfo(medicalInfo);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medical information saved successfully (encrypted)'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true); // Return true to indicate success
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save medical info: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showSkipConfirmation() async {
    final shouldSkip = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Medical Information?'),
        content: const Text(
          'Medical information can help emergency responders provide better care. '
          'You can add it later from your profile.\n\n'
          'Are you sure you want to skip?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );

    if (shouldSkip == true && mounted) {
      Navigator.pop(context, false);
    }
  }

  Widget _buildChipInput({
    required String label,
    required List<String> items,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: items
              .map(
                (item) => Chip(
                  label: Text(item),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () {
                    setState(() => items.remove(item));
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Add $label',
                  prefixIcon: Icon(icon),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty && !items.contains(value.trim())) {
                    setState(() {
                      items.add(value.trim());
                      controller.clear();
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty && !items.contains(value)) {
                  setState(() {
                    items.add(value);
                    controller.clear();
                  });
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingInfo != null ? 'Edit Medical Info' : 'Add Medical Info'),
        backgroundColor: Colors.red,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Your medical information is encrypted and only shared with dispatchers when you send an SOS.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Blood Type
                    const Text(
                      'Blood Type',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _bloodType.isEmpty ? null : _bloodType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.bloodtype),
                        hintText: 'Select blood type',
                      ),
                      items: _bloodTypes
                          .map((type) => DropdownMenuItem(
                                value: type.isEmpty ? null : type,
                                child: Text(type.isEmpty ? 'Not specified' : type),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() => _bloodType = value ?? '');
                      },
                    ),
                    const SizedBox(height: 24),

                    // Allergies
                    _buildChipInput(
                      label: 'Allergies',
                      items: _allergies,
                      controller: _allergyController,
                      icon: Icons.warning,
                    ),
                    const SizedBox(height: 24),

                    // Medications
                    _buildChipInput(
                      label: 'Current Medications',
                      items: _medications,
                      controller: _medicationController,
                      icon: Icons.medication,
                    ),
                    const SizedBox(height: 24),

                    // Medical Conditions
                    _buildChipInput(
                      label: 'Medical Conditions',
                      items: _conditions,
                      controller: _conditionController,
                      icon: Icons.local_hospital,
                    ),
                    const SizedBox(height: 24),

                    // Emergency Contact Section
                    const Text(
                      'Emergency Contact',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emergencyNameController,
                      decoration: const InputDecoration(
                        labelText: 'Contact Name',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emergencyPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact Phone',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                        hintText: '+60123456789',
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emergencyEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Contact Email (optional)',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                        hintText: 'Used if phone is unavailable',
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emergencyRelationshipController,
                      decoration: const InputDecoration(
                        labelText: 'Relationship',
                        prefixIcon: Icon(Icons.family_restroom),
                        border: OutlineInputBorder(),
                        hintText: 'e.g., Spouse, Parent, Sibling',
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Additional Notes
                    const Text(
                      'Additional Notes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Any other important medical information...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveMedicalInfo,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Save Medical Information',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                    ),
                    const SizedBox(height: 12),

                    // Skip Button (only show if creating new, not editing)
                    if (widget.existingInfo == null)
                      TextButton(
                        onPressed: _isSaving ? null : _showSkipConfirmation,
                        child: const Text('Skip for now'),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
