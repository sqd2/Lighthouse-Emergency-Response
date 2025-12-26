import 'package:flutter/material.dart';
import '../models/facility_pin.dart';

/// Widget for filtering and searching facilities
class FacilityFilterWidget extends StatefulWidget {
  final List<FacilityPin> allFacilities;
  final Function(List<FacilityPin>) onFilteredFacilities;

  const FacilityFilterWidget({
    Key? key,
    required this.allFacilities,
    required this.onFilteredFacilities,
  }) : super(key: key);

  @override
  State<FacilityFilterWidget> createState() => _FacilityFilterWidgetState();
}

class _FacilityFilterWidgetState extends State<FacilityFilterWidget> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedTypes = {};

  // All possible facility types
  static const List<String> _allTypes = [
    'Hospital',
    'Clinic',
    'Police Station',
    'Fire Station',
  ];

  @override
  void initState() {
    super.initState();
    // Initially select all types
    _selectedTypes.addAll(_allTypes);
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final searchText = _searchController.text.toLowerCase();

    final filtered = widget.allFacilities.where((facility) {
      // Filter by type
      if (!_selectedTypes.contains(facility.type)) return false;

      // Filter by search text (name or address)
      if (searchText.isNotEmpty) {
        final matchesName = facility.name.toLowerCase().contains(searchText);
        final address = facility.meta?['address']?.toString() ?? '';
        final matchesAddress = address.toLowerCase().contains(searchText);
        if (!matchesName && !matchesAddress) return false;
      }

      return true;
    }).toList();

    widget.onFilteredFacilities(filtered);
  }

  void _toggleType(String type) {
    setState(() {
      if (_selectedTypes.contains(type)) {
        _selectedTypes.remove(type);
      } else {
        _selectedTypes.add(type);
      }
    });
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search facilities...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),

          const SizedBox(height: 12),

          // Type filter chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allTypes.map((type) {
              final isSelected = _selectedTypes.contains(type);
              final color = _getColorForType(type);

              return FilterChip(
                label: Text(type),
                selected: isSelected,
                onSelected: (_) => _toggleType(type),
                backgroundColor: Colors.grey[200],
                selectedColor: color.withOpacity(0.2),
                checkmarkColor: color,
                labelStyle: TextStyle(
                  color: isSelected ? color : Colors.grey[700],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),

          // Result count
          Text(
            '${widget.allFacilities.where((f) => _selectedTypes.contains(f.type)).length} facilities',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'Hospital':
        return Colors.red;
      case 'Clinic':
        return Colors.orange;
      case 'Police Station':
        return Colors.blue;
      case 'Fire Station':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }
}
