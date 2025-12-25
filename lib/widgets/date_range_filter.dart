import 'package:flutter/material.dart';

/// Date range filter widget for filtering past alerts
class DateRangeFilter extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final ValueChanged<DateRange> onChanged;

  const DateRangeFilter({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.onChanged,
  });

  @override
  State<DateRangeFilter> createState() => _DateRangeFilterState();
}

class _DateRangeFilterState extends State<DateRangeFilter> {
  late DateRangePreset _selectedPreset;
  late DateTime _customStart;
  late DateTime _customEnd;

  @override
  void initState() {
    super.initState();
    _selectedPreset = DateRangePreset.last7Days;
    _customStart = widget.startDate;
    _customEnd = widget.endDate;
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.filter_list),
      tooltip: 'Filter by date',
      onPressed: _showFilterDialog,
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Date Range'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPresetOption(
              DateRangePreset.last7Days,
              'Last 7 Days',
              Icons.calendar_today,
            ),
            _buildPresetOption(
              DateRangePreset.last30Days,
              'Last 30 Days',
              Icons.calendar_month,
            ),
            _buildPresetOption(
              DateRangePreset.custom,
              'Custom Range',
              Icons.date_range,
            ),
            if (_selectedPreset == DateRangePreset.custom) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _buildDateButton(
                'Start Date',
                _customStart,
                (date) => setState(() => _customStart = date),
              ),
              const SizedBox(height: 8),
              _buildDateButton(
                'End Date',
                _customEnd,
                (date) => setState(() => _customEnd = date),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _applyFilter();
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetOption(
    DateRangePreset preset,
    String label,
    IconData icon,
  ) {
    final isSelected = _selectedPreset == preset;
    return InkWell(
      onTap: () => setState(() => _selectedPreset = preset),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Radio<DateRangePreset>(
              value: preset,
              groupValue: _selectedPreset,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedPreset = value);
                }
              },
            ),
            Icon(icon, size: 20, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.black,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateButton(
    String label,
    DateTime date,
    ValueChanged<DateTime> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              onChanged(picked);
            }
          },
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text(
            '${date.day}/${date.month}/${date.year}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  void _applyFilter() {
    DateTime start, end;

    switch (_selectedPreset) {
      case DateRangePreset.last7Days:
        end = DateTime.now();
        start = end.subtract(const Duration(days: 7));
        break;
      case DateRangePreset.last30Days:
        end = DateTime.now();
        start = end.subtract(const Duration(days: 30));
        break;
      case DateRangePreset.custom:
        start = _customStart;
        end = _customEnd;
        break;
    }

    widget.onChanged(DateRange(start, end));
  }
}

enum DateRangePreset {
  last7Days,
  last30Days,
  custom,
}

class DateRange {
  final DateTime start;
  final DateTime end;

  DateRange(this.start, this.end);
}
