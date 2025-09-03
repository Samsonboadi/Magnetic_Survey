import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../models/magnetic_reading.dart';
import '../models/survey_project.dart';

class DataAnalysisScreen extends StatefulWidget {
  const DataAnalysisScreen({
    super.key,
    required this.readings,
    this.project,
  });

  final List<MagneticReading> readings;
  final SurveyProject? project;

  @override
  State<DataAnalysisScreen> createState() => _DataAnalysisScreenState();
}

class _DataAnalysisScreenState extends State<DataAnalysisScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  late List<MagneticReading> _points;
  Map<String, dynamic> _statistics = {};
  List<Map<String, dynamic>> _anomalies = [];

  // Filtering options
  DateTimeRange? _dateFilter;
  double _minMagnitude = 0;
  double _maxMagnitude = 100000;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      _points = List.of(widget.readings)..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (_points.isNotEmpty) {
        _calculateStatistics();
        _detectAnomalies();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _calculateStatistics() {
    if (_points.isEmpty) return;

    final magnitudes = _points.map((p) => p.totalField).toList()..sort();
    final altitudes = _points.map((p) => p.altitude ?? 0.0).toList();
    final accuracies = _points.map((p) => p.accuracy ?? 0.0).where((v) => v > 0).toList();

    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    final variance = magnitudes
            .map((x) => math.pow(x - mean, 2))
            .reduce((a, b) => a + b) /
        magnitudes.length;
    final standardDeviation = math.sqrt(variance);

    _statistics = {
      'total_measurements': _points.length,
      'magnitude_min': magnitudes.first,
      'magnitude_max': magnitudes.last,
      'magnitude_mean': mean,
      'magnitude_std': standardDeviation,
      'magnitude_median': magnitudes.length % 2 == 0
          ? (magnitudes[magnitudes.length ~/ 2 - 1] +
                  magnitudes[magnitudes.length ~/ 2]) /
              2
          : magnitudes[magnitudes.length ~/ 2],
      'altitude_mean': altitudes.isNotEmpty
          ? altitudes.reduce((a, b) => a + b) / altitudes.length
          : 0.0,
      'gps_accuracy_mean': accuracies.isNotEmpty
          ? accuracies.reduce((a, b) => a + b) / accuracies.length
          : null,
      'duration_hours': _points.isNotEmpty
          ? _points.last.timestamp
              .difference(_points.first.timestamp)
              .inHours
          : 0,
      'survey_area_km2': _calculateSurveyArea(),
    };
  }

  double _calculateSurveyArea() {
    if (_points.length < 3) return 0.0;

    final lats = _points.map((p) => p.latitude).toList()..sort();
    final lngs = _points.map((p) => p.longitude).toList()..sort();

    final latRange = lats.last - lats.first;
    final lngRange = lngs.last - lngs.first;

    final latKm = latRange * 111.32;
    final midLat = lats[lats.length ~/ 2];
    final lngKm = lngRange * 111.32 * math.cos(midLat * math.pi / 180);

    return (latKm * lngKm).abs();
  }

  void _detectAnomalies() {
    if (_points.length < 10) return;

    _anomalies.clear();
    final mean = _statistics['magnitude_mean'] as double;
    final std = _statistics['magnitude_std'] as double;
    final threshold = std * 2; // 2 standard deviations

    for (int i = 0; i < _points.length; i++) {
      final p = _points[i];
      final deviation = (p.totalField - mean).abs();
      if (deviation > threshold) {
        _anomalies.add({
          'index': i,
          'point': p,
          'deviation': deviation,
          'severity': deviation > std * 3 ? 'High' : 'Medium',
        });
      }
    }

    _anomalies.sort(
        (a, b) => (b['deviation'] as double).compareTo(a['deviation'] as double));
    if (_anomalies.length > 20) {
      _anomalies = _anomalies.take(20).toList();
    }
  }

  void _applyFilters() {
    // Future: apply filters to _points and recompute
    setState(() {});
  }

  void _exportData() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildExportSheet(),
    );
  }

  Widget _buildExportSheet() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Export Analysis Data',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: const Text('Export as CSV'),
            subtitle: const Text('Raw measurement data'),
            onTap: () {
              Navigator.pop(context);
              _showExportMessage('CSV');
            },
          ),
          ListTile(
            leading: const Icon(Icons.insert_chart),
            title: const Text('Export Statistics'),
            subtitle: const Text('Analysis summary and statistics'),
            onTap: () {
              Navigator.pop(context);
              _showExportMessage('Statistics');
            },
          ),
          ListTile(
            leading: const Icon(Icons.warning),
            title: const Text('Export Anomalies'),
            subtitle: const Text('Detected anomalous readings'),
            onTap: () {
              Navigator.pop(context);
              _showExportMessage('Anomalies');
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showExportMessage(String type) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$type export functionality coming soon!'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project?.name ?? 'Data Analysis'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.analytics), text: 'Overview'),
            Tab(icon: Icon(Icons.show_chart), text: 'Trends'),
            Tab(icon: Icon(Icons.warning), text: 'Anomalies'),
            Tab(icon: Icon(Icons.map), text: 'Spatial'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_showFilters) _buildFilterPanel(),
          Expanded(
            child: Builder(builder: (context) {
              if (_isLoading) {
                return const _ModernLoadingIndicator(
                    message: 'Analyzing survey data...');
              }
              if (_hasError) {
                return _ModernErrorState(
                  message: _errorMessage,
                  onRetry: _loadData,
                );
              }
              if (_points.isEmpty) {
                return _ModernEmptyState(
                  message:
                      'No survey data available for analysis.\nStart collecting measurements to see analysis.',
                  icon: Icons.analytics,
                  actionText: 'Back',
                  onAction: () => Navigator.pop(context),
                );
              }
              return TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildTrendsTab(),
                  _buildAnomaliesTab(),
                  _buildSpatialTab(),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
    final theme = Theme.of(context);
    DateTime firstTs =
        _points.isNotEmpty ? _points.first.timestamp : DateTime.now();
    DateTime lastTs = _points.isNotEmpty ? _points.last.timestamp : DateTime.now();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_list, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Data Filters',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _dateFilter = null;
                    _minMagnitude = 0;
                    _maxMagnitude = 100000;
                  });
                  _applyFilters();
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_dateFilter != null ? 'Date Range Set' : 'Date Range'),
                onPressed: () async {
                  if (_points.isEmpty) return;
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: firstTs,
                    lastDate: lastTs,
                    initialDateRange: _dateFilter,
                  );
                  if (picked != null) {
                    setState(() => _dateFilter = picked);
                    _applyFilters();
                  }
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.tune, size: 18),
                label: const Text('Magnitude Range'),
                onPressed: _showMagnitudeFilter,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMagnitudeFilter() {
    double minVal =
        (_statistics['magnitude_min'] as double?)?.toDouble() ?? 0.0;
    double maxVal =
        (_statistics['magnitude_max'] as double?)?.toDouble() ?? 100000.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Magnitude Filter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Filter by magnetic field magnitude (μT)'),
            const SizedBox(height: 16),
            RangeSlider(
              values: RangeValues(_minMagnitude, _maxMagnitude),
              min: minVal,
              max: maxVal,
              divisions: 100,
              labels: RangeLabels(
                _minMagnitude.toStringAsFixed(1),
                _maxMagnitude.toStringAsFixed(1),
              ),
              onChanged: (values) {
                setState(() {
                  _minMagnitude = values.start;
                  _maxMagnitude = values.end;
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _applyFilters();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _StatCard(
                title: 'Total Points',
                value: '${_statistics['total_measurements'] ?? 0}',
                icon: Icons.analytics,
                color: Colors.blue,
                subtitle: 'Data points collected',
              ),
              _StatCard(
                title: 'Survey Duration',
                value: '${_statistics['duration_hours'] ?? 0}h',
                icon: Icons.access_time,
                color: Colors.green,
                subtitle: 'Collection time',
              ),
              _StatCard(
                title: 'Survey Area',
                value:
                    '${(((_statistics['survey_area_km2'] as double?) ?? 0).toStringAsFixed(2))} km²',
                icon: Icons.map,
                color: Colors.orange,
                subtitle: 'Coverage area',
              ),
              _StatCard(
                title: 'Anomalies Found',
                value: '${_anomalies.length}',
                icon: Icons.warning,
                color: Colors.red,
                subtitle: 'Unusual readings',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DataCard(
            title: 'Magnetic Field Statistics',
            child: Column(
              children: [
                _buildStatRow('Minimum',
                    '${(((_statistics['magnitude_min'] as double?) ?? 0).toStringAsFixed(2))} μT'),
                _buildStatRow('Maximum',
                    '${(((_statistics['magnitude_max'] as double?) ?? 0).toStringAsFixed(2))} μT'),
                _buildStatRow('Mean',
                    '${(((_statistics['magnitude_mean'] as double?) ?? 0).toStringAsFixed(2))} μT'),
                _buildStatRow('Median',
                    '${(((_statistics['magnitude_median'] as double?) ?? 0).toStringAsFixed(2))} μT'),
                _buildStatRow('Std. Deviation',
                    '${(((_statistics['magnitude_std'] as double?) ?? 0).toStringAsFixed(2))} μT'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DataCard(
            title: 'Survey Conditions',
            child: Column(
              children: [
                _buildStatRow(
                    'Avg. Altitude',
                    '${(((_statistics['altitude_mean'] as double?) ?? 0).toStringAsFixed(1))} m'),
                if (_statistics['gps_accuracy_mean'] != null)
                  _buildStatRow(
                      'Avg. GPS Accuracy',
                      '${(((_statistics['gps_accuracy_mean'] as double?) ?? 0).toStringAsFixed(1))} m'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _DataCard(
            title: 'Magnetic Field Over Time',
            child: SizedBox(
              height: 220,
              child: _TimeSeriesChart(points: _points),
            ),
          ),
          const SizedBox(height: 16),
          _DataCard(
            title: 'Field Components',
            child: SizedBox(
              height: 200,
              child: _ComponentsChart(points: _points),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomaliesTab() {
    if (_anomalies.isEmpty) {
      return const _ModernEmptyState(
        message: 'No significant anomalies detected in the survey data.',
        icon: Icons.check_circle_outline,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _anomalies.length,
      itemBuilder: (context, index) {
        final anomaly = _anomalies[index];
        final p = anomaly['point'] as MagneticReading;
        final severity = anomaly['severity'] as String;
        final deviation = anomaly['deviation'] as double;
        final severityColor = severity == 'High' ? Colors.red : Colors.orange;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: severityColor.withOpacity(0.1),
              child: Icon(
                severity == 'High' ? Icons.priority_high : Icons.warning,
                color: severityColor,
              ),
            ),
            title: Text('${p.totalField.toStringAsFixed(2)} μT'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deviation: ${deviation.toStringAsFixed(2)} μT'),
                Text(
                    'Location: ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}'),
                Text('Time: ${_formatDateTime(p.timestamp)}'),
              ],
            ),
            trailing: Chip(
              label: Text(
                severity,
                style: TextStyle(
                    color: severityColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              backgroundColor: severityColor.withOpacity(0.1),
            ),
            onTap: () => _showAnomalyDetails(anomaly),
          ),
        );
      },
    );
  }

  Widget _buildSpatialTab() {
    final center = _points.isNotEmpty
        ? LatLng(_points.first.latitude, _points.first.longitude)
        : const LatLng(0, 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _DataCard(
            title: 'Measurement Locations',
            action: IconButton(
              icon: const Icon(Icons.center_focus_strong),
              tooltip: 'Fit to data',
              onPressed: _fitMapToData,
            ),
            child: SizedBox(
              height: 300,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 3,
                  onMapReady: () => _fitMapToData(),
                  maxZoom: 18,
                  minZoom: 2,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.example.magnetic_survey_app',
                  ),
                  if (_points.isNotEmpty)
                    CircleLayer(
                      circles: _points
                          .map(
                            (p) => CircleMarker(
                              point: LatLng(p.latitude, p.longitude),
                              radius: 3,
                              color: _colorForField(p.totalField),
                              borderColor: Colors.white,
                              borderStrokeWidth: 1,
                            ),
                          )
                          .toList(),
                    ),
                  if (_anomalies.isNotEmpty)
                    MarkerLayer(
                      markers: _anomalies
                          .map((a) {
                            final p = a['point'] as MagneticReading;
                            return Marker(
                              point: LatLng(p.latitude, p.longitude),
                              child: const Icon(Icons.warning,
                                  color: Colors.orange, size: 16),
                            );
                          })
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _DataCard(
            title: 'Survey Bounds',
            child: Column(children: [_buildCoordinateInfo()]),
          ),
        ],
      ),
    );
  }

  void _fitMapToData() {
    if (_points.isEmpty) return;
    try {
      final pts = _points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList(growable: false);
      if (pts.length == 1) {
        _mapController.move(pts.first, 14.0);
        return;
      }
      final bounds = LatLngBounds.fromPoints(pts);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)),
      );
    } catch (_) {}
  }

  Color _colorForField(double field) {
    // Map 20–70 μT to a blue->red gradient
    final minF = 20.0, maxF = 70.0;
    double t = ((field - minF) / (maxF - minF)).clamp(0.0, 1.0);
    if (t < 0.3) {
      return Color.lerp(Colors.blue, Colors.cyan, t / 0.3)!;
    } else if (t < 0.5) {
      return Color.lerp(Colors.cyan, Colors.green, (t - 0.3) / 0.2)!;
    } else if (t < 0.7) {
      return Color.lerp(Colors.green, Colors.yellow, (t - 0.5) / 0.2)!;
    } else if (t < 0.85) {
      return Color.lerp(Colors.yellow, Colors.orange, (t - 0.7) / 0.15)!;
    } else {
      return Color.lerp(Colors.orange, Colors.red, (t - 0.85) / 0.15)!;
    }
  }

// ================= Charts =================

  // Coordinate info and anomaly details (moved before charts)
  Widget _buildCoordinateInfo() {
    if (_points.isEmpty) return const Text('No data available');

    final lats = _points.map((p) => p.latitude).toList()..sort();
    final lngs = _points.map((p) => p.longitude).toList()..sort();

    return Column(
      children: [
        _buildStatRow('North Bound', '${lats.last.toStringAsFixed(6)}°'),
        _buildStatRow('South Bound', '${lats.first.toStringAsFixed(6)}°'),
        _buildStatRow('East Bound', '${lngs.last.toStringAsFixed(6)}°'),
        _buildStatRow('West Bound', '${lngs.first.toStringAsFixed(6)}°'),
        const Divider(),
        _buildStatRow('Lat Range', '${(lats.last - lats.first).toStringAsFixed(6)}°'),
        _buildStatRow('Lng Range', '${(lngs.last - lngs.first).toStringAsFixed(6)}°'),
      ],
    );
  }

  void _showAnomalyDetails(Map<String, dynamic> anomaly) {
    final p = anomaly['point'] as MagneticReading;
    final deviation = anomaly['deviation'] as double;
    final severity = anomaly['severity'] as String;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anomaly Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Total Field', '${p.totalField.toStringAsFixed(3)} μT'),
            _buildDetailRow('Deviation', '${deviation.toStringAsFixed(3)} μT'),
            _buildDetailRow('Severity', severity),
            _buildDetailRow('X Component', '${(p.magneticX ?? 0).toStringAsFixed(3)} μT'),
            _buildDetailRow('Y Component', '${(p.magneticY ?? 0).toStringAsFixed(3)} μT'),
            _buildDetailRow('Z Component', '${(p.magneticZ ?? 0).toStringAsFixed(3)} μT'),
            _buildDetailRow('Latitude', '${p.latitude.toStringAsFixed(6)}°'),
            _buildDetailRow('Longitude', '${p.longitude.toStringAsFixed(6)}°'),
            if (p.altitude != null)
              _buildDetailRow('Altitude', '${p.altitude!.toStringAsFixed(1)} m'),
            _buildDetailRow('Timestamp', _formatDateTime(p.timestamp)),
            if (p.accuracy != null)
              _buildDetailRow('GPS Accuracy', '${p.accuracy!.toStringAsFixed(1)} m'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Anomaly marked for review'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Mark Reviewed'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

}

class _TimeSeriesChart extends StatelessWidget {
  const _TimeSeriesChart({required this.points});
  final List<MagneticReading> points;
  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const Center(child: Text('Not enough data to render chart'));
    }
    return CustomPaint(
      painter: _TimeSeriesChartPainter(points),
    );
  }
}

class _TimeSeriesChartPainter extends CustomPainter {
  _TimeSeriesChartPainter(this.points);
  final List<MagneticReading> points;
  @override
  void paint(Canvas canvas, Size size) {
    final padding = 28.0;
    final area = Rect.fromLTWH(padding, 8, size.width - padding - 8, size.height - padding - 16);

    // Background grid
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;
    const hLines = 4;
    for (int i = 0; i <= hLines; i++) {
      final y = area.top + i * area.height / hLines;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), gridPaint);
    }

    // Compute ranges
    final values = points.map((p) => p.totalField).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final ts0 = points.first.timestamp.millisecondsSinceEpoch.toDouble();
    final ts1 = points.last.timestamp.millisecondsSinceEpoch.toDouble();
    final span = (ts1 - ts0).abs() > 0 ? (ts1 - ts0) : 1.0;

    Offset toPoint(MagneticReading p) {
      final x = area.left + (p.timestamp.millisecondsSinceEpoch - ts0) / span * area.width;
      final y = area.bottom - ((p.totalField - minV) / ((maxV - minV) == 0 ? 1 : (maxV - minV))) * area.height;
      return Offset(x, y);
    }

    // Line path
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final pt = toPoint(points[i]);
      if (i == 0) path.moveTo(pt.dx, pt.dy);
      else path.lineTo(pt.dx, pt.dy);
    }
    final linePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, linePaint);

    // Axis labels (min/max)
    final tpMin = TextPainter(
        text: TextSpan(text: minV.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: Colors.black54)),
        textDirection: TextDirection.ltr)
      ..layout();
    final tpMax = TextPainter(
        text: TextSpan(text: maxV.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: Colors.black54)),
        textDirection: TextDirection.ltr)
      ..layout();
    tpMin.paint(canvas, Offset(4, area.bottom - tpMin.height / 2));
    tpMax.paint(canvas, Offset(4, area.top - tpMax.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ComponentsChart extends StatelessWidget {
  const _ComponentsChart({required this.points});
  final List<MagneticReading> points;
  @override
  Widget build(BuildContext context) {
    final hasAny = points.any((p) => (p.magneticX ?? 0) != 0 || (p.magneticY ?? 0) != 0 || (p.magneticZ ?? 0) != 0);
    if (points.length < 2 || !hasAny) {
      return const Center(child: Text('Component data not available'));
    }
    return CustomPaint(
      painter: _ComponentsChartPainter(points),
    );
  }
}

class _ComponentsChartPainter extends CustomPainter {
  _ComponentsChartPainter(this.points);
  final List<MagneticReading> points;
  @override
  void paint(Canvas canvas, Size size) {
    final padding = 28.0;
    final area = Rect.fromLTWH(padding, 8, size.width - padding - 8, size.height - padding - 16);
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;
    const hLines = 4;
    for (int i = 0; i <= hLines; i++) {
      final y = area.top + i * area.height / hLines;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), gridPaint);
    }

    final xs = points.map((p) => p.magneticX ?? 0.0).toList();
    final ys = points.map((p) => p.magneticY ?? 0.0).toList();
    final zs = points.map((p) => p.magneticZ ?? 0.0).toList();
    final all = <double>[]..addAll(xs)..addAll(ys)..addAll(zs);
    final minV = all.reduce(math.min);
    final maxV = all.reduce(math.max);
    final ts0 = points.first.timestamp.millisecondsSinceEpoch.toDouble();
    final ts1 = points.last.timestamp.millisecondsSinceEpoch.toDouble();
    final span = (ts1 - ts0).abs() > 0 ? (ts1 - ts0) : 1.0;

    Offset toPoint(double v, DateTime ts) {
      final x = area.left + (ts.millisecondsSinceEpoch - ts0) / span * area.width;
      final y = area.bottom - ((v - minV) / ((maxV - minV) == 0 ? 1 : (maxV - minV))) * area.height;
      return Offset(x, y);
    }

    void drawSeries(List<double> series, Color color) {
      final path = Path();
      for (int i = 0; i < points.length; i++) {
        final pt = toPoint(series[i], points[i].timestamp);
        if (i == 0) path.moveTo(pt.dx, pt.dy); else path.lineTo(pt.dx, pt.dy);
      }
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawPath(path, paint);
    }

    drawSeries(xs, Colors.blue);
    drawSeries(ys, Colors.orange);
    drawSeries(zs, Colors.green);

    final legendStyle = const TextStyle(fontSize: 10, color: Colors.black87);
    final legendY = area.top - 2;
    _legend(canvas, Offset(area.right - 110, legendY), Colors.blue, 'X', legendStyle);
    _legend(canvas, Offset(area.right - 70, legendY), Colors.orange, 'Y', legendStyle);
    _legend(canvas, Offset(area.right - 30, legendY), Colors.green, 'Z', legendStyle);
  }

  void _legend(Canvas canvas, Offset pos, Color color, String label, TextStyle style) {
    final paint = Paint()..color = color..strokeWidth = 3;
    canvas.drawLine(pos, pos + const Offset(16, 0), paint);
    final tp = TextPainter(text: TextSpan(text: label, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, pos + const Offset(20, -6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Lightweight versions of the "modern" widgets used in the screen
class _ModernLoadingIndicator extends StatelessWidget {
  const _ModernLoadingIndicator({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(message),
        ],
      ),
    );
  }
}

class _ModernErrorState extends StatelessWidget {
  const _ModernErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ModernEmptyState extends StatelessWidget {
  const _ModernEmptyState({
    required this.message,
    required this.icon,
    this.actionText,
    this.onAction,
  });
  final String message;
  final IconData icon;
  final String? actionText;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionText != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionText!)),
          ]
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
