import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddFacilityScreen extends StatefulWidget {
  final double? presetLat;
  final double? presetLon;

  const AddFacilityScreen({super.key, this.presetLat, this.presetLon});

  @override
  State<AddFacilityScreen> createState() => _AddFacilityScreenState();
}

class _AddFacilityScreenState extends State<AddFacilityScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _servicesController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactNumberController = TextEditingController();

  String _selectedCategory = 'Hospital';

  Future<void> _saveFacility() async {
    if (widget.presetLat == null || widget.presetLon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not set. Tap map to choose a place first.'),
        ),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      await FirebaseFirestore.instance.collection('facilities').add({
        'name': _nameController.text.trim(),
        'category': _selectedCategory,
        'description': _descController.text.trim(),
        'services': _servicesController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'contactPerson': _contactNameController.text.trim(),
        'contactNumber': _contactNumberController.text.trim(),
        'location': GeoPoint(widget.presetLat!, widget.presetLon!),
        'addedBy': user.uid,
        'createdAt': Timestamp.now(),
        'source': 'custom',
      });

      if (mounted) {
        Navigator.pop(context, true); // true signals "saved"
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save facility: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final latText = widget.presetLat?.toStringAsFixed(6) ?? '-';
    final lonText = widget.presetLon?.toStringAsFixed(6) ?? '-';

    return Scaffold(
      appBar: AppBar(title: const Text('Add Facility')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              "Selected location: $latText, $lonText",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Facility Name'),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: _selectedCategory,
              items: const [
                DropdownMenuItem(value: 'Hospital', child: Text('Hospital')),
                DropdownMenuItem(value: 'Clinic', child: Text('Clinic')),
                DropdownMenuItem(
                  value: 'Fire Station',
                  child: Text('Fire Station'),
                ),
                DropdownMenuItem(
                  value: 'Police Station',
                  child: Text('Police Station'),
                ),
                DropdownMenuItem(value: 'Shelter', child: Text('Shelter')),
              ],
              onChanged: (v) => setState(() => _selectedCategory = v!),
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _servicesController,
              decoration: const InputDecoration(
                labelText: 'Services (comma-separated)',
              ),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _contactNameController,
              decoration: const InputDecoration(labelText: 'Contact Person'),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _contactNumberController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Contact Number'),
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: _saveFacility,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Save Facility'),
            ),
          ],
        ),
      ),
    );
  }
}
