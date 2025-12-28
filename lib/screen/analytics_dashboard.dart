import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/analytics_service.dart';

/// Analytics dashboard for dispatchers to view system metrics and performance
class AnalyticsDashboard extends StatefulWidget {
  const AnalyticsDashboard({super.key});

  @override
  State<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends State<AnalyticsDashboard> {
  final AnalyticsService _analyticsService = AnalyticsService();

  // Time period selection
  String _selectedPeriod = 'week'; // today, week, month
  bool _isLoading = true;

  // Metrics data
  int _totalAlerts = 0;
  double _avgResponseTime = 0.0;
  int _activeDispatchers = 0;
  double _successRate = 0.0;
  Map<String, int> _alertsByStatus = {};
  Map<DateTime, int> _alertTrend = {};
  List<Map<String, dynamic>> _topDispatchers = [];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      DateTime startDate;

      switch (_selectedPeriod) {
        case 'today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          startDate = now.subtract(const Duration(days: 30));
          break;
        default:
          startDate = now.subtract(const Duration(days: 7));
      }

      // Fetch all metrics in parallel
      final results = await Future.wait([
        _analyticsService.getTotalAlerts(startDate: startDate),
        _analyticsService.getAverageResponseTime(startDate: startDate),
        _analyticsService.getActiveDispatchersCount(),
        _analyticsService.getSuccessRate(startDate: startDate),
        _analyticsService.getAlertsByStatus(startDate: startDate),
        _analyticsService.getAlertTrend(days: 7),
        _analyticsService.getTopDispatchers(limit: 5),
      ]);

      if (mounted) {
        setState(() {
          _totalAlerts = results[0] as int;
          _avgResponseTime = results[1] as double;
          _activeDispatchers = results[2] as int;
          _successRate = results[3] as double;
          _alertsByStatus = results[4] as Map<String, int>;
          _alertTrend = results[5] as Map<DateTime, int>;
          _topDispatchers = results[6] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AnalyticsDashboard] Error loading analytics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadAnalytics,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time period selector
                  _buildPeriodSelector(),
                  const SizedBox(height: 20),

                  // Metric cards
                  _buildMetricCards(),
                  const SizedBox(height: 24),

                  // Alert Status Breakdown (Pie Chart)
                  const Text(
                    'Alert Status Breakdown',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildStatusPieChart(),
                  const SizedBox(height: 24),

                  // Alert Trend (Last 7 Days)
                  const Text(
                    'Alert Trend (Last 7 Days)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildTrendLineChart(),
                  const SizedBox(height: 24),

                  // Top Dispatchers Leaderboard
                  const Text(
                    'Top Dispatchers',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildTopDispatchers(),
                ],
              ),
            ),
          );
  }

  Widget _buildPeriodSelector() {
    return Row(
      children: [
        const Text(
          'Time Period:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'today', label: Text('Today')),
              ButtonSegment(value: 'week', label: Text('Week')),
              ButtonSegment(value: 'month', label: Text('Month')),
            ],
            selected: {_selectedPeriod},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _selectedPeriod = newSelection.first;
              });
              _loadAnalytics();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCards() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildMetricCard(
          'Total Alerts',
          _totalAlerts.toString(),
          Icons.warning_amber,
          Colors.orange,
        ),
        _buildMetricCard(
          'Avg Response Time',
          _formatDuration(_avgResponseTime),
          Icons.timer,
          Colors.blue,
        ),
        _buildMetricCard(
          'Active Dispatchers',
          _activeDispatchers.toString(),
          Icons.people,
          Colors.green,
        ),
        _buildMetricCard(
          'Success Rate',
          '${_successRate.toStringAsFixed(1)}%',
          Icons.check_circle,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const Spacer(),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPieChart() {
    if (_alertsByStatus.isEmpty || _alertsByStatus.values.every((v) => v == 0)) {
      return Container(
        height: 250,
        alignment: Alignment.center,
        child: const Text('No data available'),
      );
    }

    final statusColors = {
      'pending': Colors.orange,
      'active': Colors.blue,
      'arrived': Colors.purple,
      'resolved': Colors.green,
      'cancelled': Colors.grey,
    };

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: PieChart(
        PieChartData(
          sections: _alertsByStatus.entries
              .where((entry) => entry.value > 0)
              .map((entry) {
            final percentage = (_totalAlerts > 0)
                ? (entry.value / _totalAlerts * 100)
                : 0.0;

            return PieChartSectionData(
              value: entry.value.toDouble(),
              title: '${percentage.toStringAsFixed(0)}%',
              color: statusColors[entry.key] ?? Colors.grey,
              radius: 100,
              titleStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          }).toList(),
          sectionsSpace: 2,
          centerSpaceRadius: 0,
        ),
      ),
    );
  }

  Widget _buildTrendLineChart() {
    if (_alertTrend.isEmpty) {
      return Container(
        height: 250,
        alignment: Alignment.center,
        child: const Text('No data available'),
      );
    }

    final sortedEntries = _alertTrend.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = sortedEntries
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value.toDouble()))
        .toList();

    final maxY = sortedEntries.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? maxY / 4 : 1,
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < sortedEntries.length) {
                    final date = sortedEntries[index].key;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        DateFormat('MM/dd').format(date),
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: maxY > 0 ? maxY + 2 : 10,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.red,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.red.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopDispatchers() {
    if (_topDispatchers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Text('No dispatcher data available'),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: _topDispatchers.asMap().entries.map((entry) {
          final index = entry.key;
          final dispatcher = entry.value;
          final email = dispatcher['email'] as String;
          final alertsResolved = dispatcher['alertsResolved'] as int;
          final avgResponseTime = dispatcher['averageResponseTime'] as double;

          final medalIcons = [
            Icons.emoji_events, // Gold
            Icons.emoji_events, // Silver
            Icons.emoji_events, // Bronze
          ];

          final medalColors = [
            Colors.amber, // Gold
            Colors.grey, // Silver
            Colors.brown, // Bronze
          ];

          return ListTile(
            leading: index < 3
                ? Icon(
                    medalIcons[index],
                    color: medalColors[index],
                    size: 32,
                  )
                : CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    child: Text('${index + 1}'),
                  ),
            title: Text(
              email,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Avg Response: ${_formatDuration(avgResponseTime)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$alertsResolved resolved',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) {
      return '${seconds.toInt()}s';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final secs = (seconds % 60).toInt();
      return '${minutes}m ${secs}s';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = ((seconds % 3600) ~/ 60);
      return '${hours}h ${minutes}m';
    }
  }
}
