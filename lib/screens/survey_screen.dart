// lib/screens/survey_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../models/magnetic_reading.dart';
import '../models/survey_project.dart';
import '../models/grid_cell.dart';
import '../models/team_member.dart';
import '../services/database_service.dart';
import '../services/sensor_service.dart';
import '../services/team_sync_service.dart';
import '../services/export_service.dart';
import '../widgets/field_notes_dialog.dart';
import '../widgets/team_panel.dart';

class SurveyScreen extends StatefulWidget {
  final SurveyProject? project;

  SurveyScreen({this.project});

  @override
  _SurveyScreenState createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  double? _heading;
  final bool _isWebMode = kIsWeb;

  // Survey data
  List<LatLng> _collectedPoints = [];
  List<GridCell> _gridCells = [];
  List<TeamMember> _teamMembers = [];
  GridCell? _currentCell;
  GridCell? _nextTargetCell;

  // Sensor data
  double _magneticX = 0.0;
  double _magneticY = 0.0;
  double _magneticZ = 0.0;
  double _totalField = 0.0;

  // Survey stats
  int _pointCount = 0;
  int _completedCells = 0;
  double _coveragePercentage = 0.0;

  // UI state
  bool _showGrid = true;
  bool _showTeamMembers = true;
  bool _autoNavigate = true;
  bool _isCollecting = false;
  bool _isTeamMode = false;
  String _surveyMode = 'manual';

  // Services
  final TeamSyncService _teamService = TeamSyncService.instance;
  final ExportService _exportService = ExportService.instance;

  @override
  void initState() {
    super.initState();
    _initializeSurvey();
    _setupTeamSync();
  }

  void _initializeSurvey() {
    if (!_isWebMode) {
      _initializeLocation();
      _startSensorListening();
    } else {
      _simulateDataForWeb();
    }
    _createSampleGrid();
  }

  void _setupTeamSync() {
    _teamService.teamMembersStream.listen((members) {
      setState(() {
        _teamMembers = members;
      });
    });
  }

  void _createSampleGrid() {
    // Create a 4x4 survey grid
    List<GridCell> cells = [];
    LatLng center = _isWebMode ? LatLng(5.6037, -0.1870) : LatLng(40.7589, -73.9851);

    double spacing = 0.0008; // ~80m

    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        LatLng cellCenter = LatLng(
          center.latitude + (i - 1.5) * spacing,
          center.longitude + (j - 1.5) * spacing,
        );

        cells.add(GridCell(
          id: '${i}_${j}',
          centerLat: cellCenter.latitude,
          centerLon: cellCenter.longitude,
          bounds: _createCellBounds(cellCenter, spacing),
          status: GridCellStatus.notStarted,
        ));
      }
    }

    setState(() {
      _gridCells = cells;
      _nextTargetCell = cells.first;
    });
  }

  List<LatLng> _createCellBounds(LatLng center, double spacing) {
    double halfSpacing = spacing / 2;
    return [
      LatLng(center.latitude - halfSpacing, center.longitude - halfSpacing),
      LatLng(center.latitude - halfSpacing, center.longitude + halfSpacing),
      LatLng(center.latitude + halfSpacing, center.longitude + halfSpacing),
      LatLng(center.latitude + halfSpacing, center.longitude - halfSpacing),
    ];
  }

  void _simulateDataForWeb() {
    _currentPosition = Position(
      latitude: 5.6037,
      longitude: -0.1870,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 100.0,
      heading: 45.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
      isMocked: true, // required by newer geolocator
    );

    _heading = 45.0;
    _magneticX = 25.5;
    _magneticY = 12.3;
    _magneticZ = 45.2;
    _totalField = SensorService.calculateTotalField(_magneticX, _magneticY, _magneticZ);

    setState(() {});
  }

  void _initializeLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission != LocationPermission.denied) {
      Position position = await Geolocator.getCurrentPosition();
      _updatePosition(position);

      _mapController.move(LatLng(position.latitude, position.longitude), 18.0);

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
        ),
      ).listen((Position position) {
        _updatePosition(position);
      });
    }
  }

  void _updatePosition(Position position) {
    setState(() {
      _currentPosition = position;
    });

    _updateCurrentCell();

    // Update team position
    if (_isTeamMode) {
      _teamService.updateMyPosition(
        LatLng(position.latitude, position.longitude),
        _heading,
      );
    }

    if (_isCollecting && _surveyMode == 'auto') {
      _recordMagneticReading();
    }
  }

  void _updateCurrentCell() {
    if (_currentPosition == null) return;

    LatLng currentPos =
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    for (GridCell cell in _gridCells) {
      if (_isPointInCell(currentPos, cell)) {
        if (_currentCell?.id != cell.id) {
          setState(() {
            if (_currentCell != null &&
                _currentCell!.status == GridCellStatus.inProgress) {
              _currentCell!.status = GridCellStatus.completed;
              _currentCell!.completedTime = DateTime.now();
              _completedCells++;
            }

            _currentCell = cell;
            if (cell.status == GridCellStatus.notStarted) {
              cell.status = GridCellStatus.inProgress;
              cell.startTime = DateTime.now();
            }

            _findNextTargetCell();
            _updateCoverageStats();

            // Notify team about cell update
            if (_isTeamMode) {
              _teamService.updateGridCell(cell);
            }
          });
        }
        break;
      }
    }
  }

  bool _isPointInCell(LatLng point, GridCell cell) {
    List<LatLng> bounds = cell.bounds;
    double minLat =
        bounds.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat =
        bounds.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLon =
        bounds.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLon =
        bounds.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    return point.latitude >= minLat &&
        point.latitude <= maxLat &&
        point.longitude >= minLon &&
        point.longitude <= maxLon;
  }

  void _findNextTargetCell() {
    GridCell? nextCell = _gridCells.firstWhere(
      (cell) => cell.status == GridCellStatus.notStarted,
      orElse: () => _gridCells.first,
    );

    setState(() {
      _nextTargetCell = nextCell;
    });
  }

  void _updateCoverageStats() {
    int completed = _gridCells
        .where((cell) => cell.status == GridCellStatus.completed)
        .length;
    setState(() {
      _completedCells = completed;
      _coveragePercentage = (completed / _gridCells.length) * 100;
    });
  }

  void _startSensorListening() {
    magnetometerEvents.listen((MagnetometerEvent event) {
      setState(() {
        _magneticX = event.x;
        _magneticY = event.y;
        _magneticZ = event.z;
        _totalField =
            SensorService.calculateTotalField(event.x, event.y, event.z);
      });
    });

    FlutterCompass.events?.listen((CompassEvent event) {
      setState(() {
        _heading = event.heading;
      });
    });
  }

  Future<void> _recordMagneticReading() async {
    if (_currentPosition == null) return;

    MagneticReading reading = MagneticReading(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      altitude: _currentPosition!.altitude,
      magneticX: _magneticX,
      magneticY: _magneticY,
      magneticZ: _magneticZ,
      totalField: _totalField,
      timestamp: DateTime.now(),
      projectId: widget.project?.id ?? 1,
    );

    if (!_isWebMode) {
      await DatabaseService.instance.insertMagneticReading(reading);
    }

    setState(() {
      _collectedPoints.add(LatLng(reading.latitude, reading.longitude));
      _pointCount++;

      // Update current cell point count
      if (_currentCell != null) {
        _currentCell!.pointCount++;
      }

      if (_isWebMode) {
        _magneticX += (0.5 - 1.0) * 2;
        _magneticY += (0.5 - 1.0) * 2;
        _magneticZ += (0.5 - 1.0) * 2;
        _totalField =
            SensorService.calculateTotalField(_magneticX, _magneticY, _magneticZ);
      }
    });
  }

  void _toggleDataCollection() {
    setState(() {
      _isCollecting = !_isCollecting;
      _surveyMode = _isCollecting ? 'auto' : 'manual';
    });

    if (_isCollecting) {
      _startAutomaticCollection();
    }
  }

  void _startAutomaticCollection() {
    Future.doWhile(() async {
      if (!_isCollecting) return false;

      await Future.delayed(const Duration(seconds: 2));
      if (_isCollecting) {
        await _recordMagneticReading();
      }
      return _isCollecting;
    });
  }

  @override
  Widget build(BuildContext context) {
    final LatLng initialCenter = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : LatLng(5.6037, -0.1870);

    return Scaffold(
      appBar: AppBar(
        title: Text('Survey - ${widget.project?.name ?? 'Default'}'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showGrid ? Icons.grid_off : Icons.grid_on),
            onPressed: () => setState(() => _showGrid = !_showGrid),
          ),
          IconButton(
            icon: const Icon(Icons.note_add),
            onPressed: _showFieldNotesDialog,
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _showExportOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          Expanded(flex: 3, child: _buildMapView(initialCenter)),
          _buildControlPanel(),
        ],
      ),
      bottomSheet:
          _isTeamMode ? TeamPanel(onTeamModeToggle: _onTeamModeToggle) : null,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_isTeamMode)
            FloatingActionButton(
              heroTag: "team",
              onPressed: () => _showBottomSheet(),
              child: const Icon(Icons.group),
              backgroundColor: Colors.purple,
              mini: true,
            ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "record",
            onPressed: _recordMagneticReading,
            child: const Icon(Icons.add_location),
            backgroundColor: Colors.green,
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "auto",
            onPressed: _toggleDataCollection,
            child: Icon(_isCollecting ? Icons.pause : Icons.play_arrow),
            backgroundColor: _isCollecting ? Colors.red : Colors.blue[800],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatusItem(
            'Coverage',
            '${_coveragePercentage.toStringAsFixed(0)}%',
            _coveragePercentage > 75
                ? Colors.green
                : _coveragePercentage > 25
                    ? Colors.orange
                    : Colors.red,
          ),
          _buildStatusItem('Points', '$_pointCount', Colors.blue),
          _buildStatusItem('Field', '${_totalField.toStringAsFixed(0)} μT',
              Colors.purple),
          if (_isTeamMode)
            _buildStatusItem('Team', '${_teamMembers.length}', Colors.green),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildMapView(LatLng initialCenter) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // flutter_map v6+ uses initialCenter/initialZoom
        initialCenter: initialCenter,
        initialZoom: 18.0,
        maxZoom: 20.0,
        minZoom: 10.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          // userAgentPackageName: 'com.example.app', // optional but recommended
        ),

        // Grid overlay
        if (_showGrid)
          PolygonLayer(
            polygons: _gridCells
                .map(
                  (cell) => Polygon(
                    points: cell.bounds,
                    color: _getCellColor(cell.status).withOpacity(0.3),
                    borderColor: _getCellColor(cell.status),
                    borderStrokeWidth: 2.0,
                  ),
                )
                .toList(),
          ),

        // Collected points
        CircleLayer(
          circles: _collectedPoints
              .map(
                (point) => CircleMarker(
                  point: point,
                  radius: 4,
                  color: Colors.green,
                  borderColor: Colors.white,
                  borderStrokeWidth: 1,
                ),
              )
              .toList(),
        ),

        // Team members positions
        if (_showTeamMembers && _isTeamMode)
          MarkerLayer(
            markers: _teamMembers
                .where((member) =>
                    member.currentPosition != null &&
                    member.id != _teamService.currentUserId)
                .map(
                  (member) => Marker(
                    point: member.currentPosition!,
                    width: 25,
                    height: 25,
                    child: Transform.rotate(
                      angle: (member.heading ?? 0) * 3.14159 / 180,
                      child: Container(
                        decoration: BoxDecoration(
                          color: member.markerColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            member.name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),

        // Current position with heading
        if (_currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
                width: 30,
                height: 30,
                child: Transform.rotate(
                  angle: (_heading ?? 0) * 3.14159 / 180,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.navigation,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),

        // Next target indicator
        if (_nextTargetCell != null && _autoNavigate)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(_nextTargetCell!.centerLat, _nextTargetCell!.centerLon),
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child:
                      const Icon(Icons.flag, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Color _getCellColor(GridCellStatus status) {
    switch (status) {
      case GridCellStatus.completed:
        return Colors.green;
      case GridCellStatus.inProgress:
        return Colors.orange;
      case GridCellStatus.notStarted:
      default:
        return Colors.red;
    }
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Current cell info
          if (_currentCell != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getCellColor(_currentCell!.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getCellColor(_currentCell!.status)),
              ),
              child: Row(
                children: [
                  Icon(_getCellIcon(_currentCell!.status),
                      color: _getCellColor(_currentCell!.status)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cell ${_currentCell!.id}: ${_currentCell!.status.toString().split('.').last} (${_currentCell!.pointCount} points)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Navigation help
          if (_nextTargetCell != null && _autoNavigate)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.navigation, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text('Next Target: Cell ${_nextTargetCell!.id}'),
                  const Spacer(),
                  if (_currentPosition != null)
                    Text(
                      '${_calculateDistance(_currentPosition!, LatLng(_nextTargetCell!.centerLat, _nextTargetCell!.centerLon)).toStringAsFixed(0)}m',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Survey controls
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _showGrid = !_showGrid),
                  icon: Icon(_showGrid ? Icons.grid_off : Icons.grid_on),
                  label: Text(_showGrid ? 'Hide Grid' : 'Show Grid'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _showGrid ? Colors.green : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _autoNavigate = !_autoNavigate),
                  icon: const Icon(Icons.assistant_navigation),
                  label: Text(_autoNavigate ? 'Auto Nav' : 'Manual'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _autoNavigate ? Colors.blue : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          if (_isTeamMode) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        setState(() => _showTeamMembers = !_showTeamMembers),
                    icon: Icon(
                        _showTeamMembers ? Icons.group_off : Icons.group),
                    label:
                        Text(_showTeamMembers ? 'Hide Team' : 'Show Team'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _showTeamMembers ? Colors.purple : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showBottomSheet,
                    icon: const Icon(Icons.people),
                    label: const Text('Team Panel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _getCellIcon(GridCellStatus status) {
    switch (status) {
      case GridCellStatus.completed:
        return Icons.check_circle;
      case GridCellStatus.inProgress:
        return Icons.radio_button_checked;
      case GridCellStatus.notStarted:
      default:
        return Icons.radio_button_unchecked;
    }
  }

  double _calculateDistance(Position from, LatLng to) {
    return Geolocator.distanceBetween(
        from.latitude, from.longitude, to.latitude, to.longitude);
  }

  void _showFieldNotesDialog() {
    showDialog(
      context: context,
      builder: (context) => FieldNotesDialog(
        onNoteSaved: (note) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Field note saved: ${note.substring(0, 20)}...')),
          );
        },
      ),
    );
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Export Survey Data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Export format options
            _buildExportOption('CSV Format', 'Spreadsheet compatible',
                Icons.table_chart, ExportFormat.csv),
            _buildExportOption(
                'GeoJSON', 'GIS compatible', Icons.map, ExportFormat.geojson),
            _buildExportOption('KML/Google Earth', 'View in Google Earth',
                Icons.public, ExportFormat.kml),

            if (!kIsWeb) ...[
              _buildExportOption('SQLite Database', 'Complete database',
                  Icons.storage, ExportFormat.sqlite),
              _buildExportOption('Shapefile (WKT)', 'GIS shapefile format',
                  Icons.layers, ExportFormat.shapefile),
            ],

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _exportData(ExportFormat.csv); // Default to CSV
                    },
                    child: const Text('Quick CSV Export'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption(
      String title, String description, IconData icon, ExportFormat format) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title),
      subtitle: Text(description),
      onTap: () {
        Navigator.pop(context);
        _exportData(format);
      },
    );
  }

  Future<void> _exportData(ExportFormat format) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Exporting data...'),
            ],
          ),
        ),
      );

      // Get project data
      SurveyProject project = widget.project ??
          SurveyProject(
            id: 1,
            name: 'Default Survey',
            description: 'Magnetic survey data',
            createdAt: DateTime.now(),
          );

      // For demo, create sample readings from collected points
      List<MagneticReading> readings =
          _collectedPoints.asMap().entries.map((entry) {
        int index = entry.key;
        LatLng point = entry.value;
        return MagneticReading(
          id: index,
          latitude: point.latitude,
          longitude: point.longitude,
          altitude: 100.0,
          magneticX: _magneticX + (index * 0.1),
          magneticY: _magneticY + (index * 0.1),
          magneticZ: _magneticZ + (index * 0.1),
          totalField: _totalField + (index * 0.5),
          timestamp:
              DateTime.now().subtract(Duration(minutes: _collectedPoints.length - index)),
          projectId: project.id ?? 1,
        );
      }).toList();

      // Export data
      String exportData = await _exportService.exportProject(
        project: project,
        readings: readings,
        gridCells: _gridCells,
        fieldNotes: [], // Empty for demo
        format: format,
      );

      // Hide loading
      Navigator.pop(context);

      // Generate filename
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String filename =
          '${project.name}_$timestamp${_exportService.getFileExtension(format)}';

      // Save and share
      await _exportService.saveAndShare(
        data: exportData,
        filename: filename,
        mimeType: _exportService.getMimeType(format),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Data exported successfully!'),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () {
              // Additional sharing options
            },
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Hide loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onTeamModeToggle(bool enabled) {
    setState(() {
      _isTeamMode = enabled;
    });
  }

  void _showBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => TeamPanel(onTeamModeToggle: _onTeamModeToggle),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
