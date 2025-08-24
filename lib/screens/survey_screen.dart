import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart' show FileImage;

// CONDITIONAL IMPORTS - Only import for the platforms that support them
import 'dart:io' as io show File; // Only available on mobile/desktop
// REMOVED: import 'dart:html' as html; - This should only be imported conditionally

import '../models/magnetic_reading.dart';
import '../models/survey_project.dart';
import '../models/grid_cell.dart';
import '../models/team_member.dart';
import '../models/field_note.dart';
import '../services/database_service.dart';
import '../services/sensor_service.dart';
import '../services/team_sync_service.dart';
import '../services/export_service.dart';
import '../widgets/team_panel.dart';

enum MapBaseLayer {
  openStreetMap,
  satellite,
  emag2Magnetic,
}

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
  List<MagneticReading> _savedReadings = [];
  GridCell? _currentCell;
  GridCell? _nextTargetCell;

  // Sensor data
  double _magneticX = 0.0;
  double _magneticY = 0.0;
  double _magneticZ = 0.0;
  double _totalField = 0.0;

  // Calibration data
  double _magneticCalibrationX = 0.0;
  double _magneticCalibrationY = 0.0;
  double _magneticCalibrationZ = 0.0;
  bool _isMagneticCalibrated = false;
  bool _isGpsCalibrated = false;
  double _gpsAccuracy = 0.0;

  // Survey stats
  int _pointCount = 0;
  int _completedCells = 0;
  double _coveragePercentage = 0.0;

  // UI state
  bool _showGrid = true;
  bool _showTeamMembers = true;
  bool _showCompass = true;
  bool _autoNavigate = true;
  bool _isCollecting = false;
  bool _isTeamMode = false;
  String _surveyMode = 'manual';
  MapBaseLayer _currentBaseLayer = MapBaseLayer.openStreetMap;

  // Settings
  Duration _magneticPullRate = Duration(seconds: 1);
  Timer? _automaticCollectionTimer;

  // Services
  final TeamSyncService _teamService = TeamSyncService.instance;
  final ExportService _exportService = ExportService.instance;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeSurvey();
    _setupTeamSync();
    _loadPreviousSurveyData();
  }

  @override
  void dispose() {
    _automaticCollectionTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ==================== INITIALIZATION ====================

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
        _isTeamMode = members.isNotEmpty;
      });
    });
  }

  Future<void> _loadPreviousSurveyData() async {
    if (widget.project != null && !_isWebMode) {
      try {
        final readings = await DatabaseService.instance.getReadingsForProject(widget.project!.id!);
        setState(() {
          _savedReadings = readings;
          _collectedPoints.addAll(readings.map((r) => LatLng(r.latitude, r.longitude)));
          _pointCount = readings.length;
        });
        _updateCoverageStats();
      } catch (e) {
        print('Error loading previous survey data: $e');
      }
    }
  }

  Future<void> _initializeLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        
        setState(() {
          _currentPosition = position;
          _gpsAccuracy = position.accuracy;
          _isGpsCalibrated = position.accuracy < 5.0;
        });

        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1,
          ),
        ).listen((Position position) {
          setState(() {
            _currentPosition = position;
            _gpsAccuracy = position.accuracy;
            
            if (position.accuracy > 10.0) {
              _showGpsGuidance();
            }
          });
          
          if (_isTeamMode) {
            _teamService.updateMyPosition(LatLng(position.latitude, position.longitude), _heading);
          }
        });
      }
    } catch (e) {
      print('Location error: $e');
    }
  }

  void _startSensorListening() {
    magnetometerEvents.listen((MagnetometerEvent event) {
      setState(() {
        _magneticX = event.x - _magneticCalibrationX;
        _magneticY = event.y - _magneticCalibrationY;
        _magneticZ = event.z - _magneticCalibrationZ;
        _totalField = SensorService.calculateTotalField(_magneticX, _magneticY, _magneticZ);
      });
    });

    FlutterCompass.events?.listen((CompassEvent event) {
      setState(() {
        _heading = event.heading;
      });
    });
  }

  void _simulateDataForWeb() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted || !_isCollecting) {
        timer.cancel();
        return;
      }
      setState(() {
        _magneticX = 25.0 + (math.Random().nextDouble() - 0.5) * 10;
        _magneticY = 15.0 + (math.Random().nextDouble() - 0.5) * 10;
        _magneticZ = 35.0 + (math.Random().nextDouble() - 0.5) * 10;
        _totalField = SensorService.calculateTotalField(_magneticX, _magneticY, _magneticZ);
        _heading = (math.Random().nextDouble() * 360);
        _gpsAccuracy = 2.0 + math.Random().nextDouble() * 3;
      });
    });
  }

void _createSampleGrid() {
  List<GridCell> cells = [];

  // Determine the grid center: use web demo coords if web mode,
  // otherwise use current device position (fallback to Accra if null).
  LatLng center = _isWebMode
      ? LatLng(5.6037, -0.1870) // Sample location in Ghana
      : (_currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : LatLng(5.6037, -0.1870));

  double cellSize = 0.0001; // ~10 meters in degrees
  int gridSize = 4; // Creates gridSize x gridSize cells

  double halfGrid = gridSize / 2.0;

  for (int i = 0; i < gridSize; i++) {
    for (int j = 0; j < gridSize; j++) {
      // Shift so grid is centered on 'center'
      double lat = center.latitude + (i - halfGrid) * cellSize;
      double lon = center.longitude + (j - halfGrid) * cellSize;

      List<LatLng> bounds = [
        LatLng(lat, lon),
        LatLng(lat + cellSize, lon),
        LatLng(lat + cellSize, lon + cellSize),
        LatLng(lat, lon + cellSize),
      ];

      // Calculate center coordinates
      double centerLat = lat + cellSize / 2;
      double centerLon = lon + cellSize / 2;

      GridCell cell = GridCell(
        id: 'cell_${i}_${j}',
        centerLat: centerLat, // Pass centerLat
        centerLon: centerLon, // Pass centerLon
        bounds: bounds,
        status: GridCellStatus.notStarted,
        pointCount: 0,
        notes: null, // Optional, explicitly set to null if not used
      );

      cells.add(cell);
    }
  }

  setState(() {
    _gridCells = cells;
  });

  _findNextTargetCell();
}

  // ==================== CALIBRATION ====================

  void _calibrateMagnetic() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Magnetic Calibration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_input_component, size: 64, color: Colors.blue),
            SizedBox(height: 16),
            Text('Hold device away from metal objects and press calibrate.'),
            SizedBox(height: 8),
            Text('Current readings:'),
            Text('X: ${_magneticX.toStringAsFixed(1)} μT'),
            Text('Y: ${_magneticY.toStringAsFixed(1)} μT'),
            Text('Z: ${_magneticZ.toStringAsFixed(1)} μT'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _magneticCalibrationX = _magneticX;
                _magneticCalibrationY = _magneticY;
                _magneticCalibrationZ = _magneticZ;
                _isMagneticCalibrated = true;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Magnetic sensor calibrated successfully')),
              );
            },
            child: Text('Calibrate'),
          ),
        ],
      ),
    );
  }

  void _checkGpsQuality() {
    String message;
    String action = '';
    
    if (_gpsAccuracy < 3.0) {
      message = 'GPS signal excellent (±${_gpsAccuracy.toStringAsFixed(1)}m)';
      setState(() => _isGpsCalibrated = true);
    } else if (_gpsAccuracy < 5.0) {
      message = 'GPS signal good (±${_gpsAccuracy.toStringAsFixed(1)}m)';
      setState(() => _isGpsCalibrated = true);
    } else if (_gpsAccuracy < 10.0) {
      message = 'GPS signal fair (±${_gpsAccuracy.toStringAsFixed(1)}m)';
      action = 'Move away from buildings for better accuracy.';
      setState(() => _isGpsCalibrated = false);
    } else {
      message = 'GPS signal poor (±${_gpsAccuracy.toStringAsFixed(1)}m)';
      action = 'Move to open area away from trees and buildings.';
      setState(() => _isGpsCalibrated = false);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('GPS Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isGpsCalibrated ? Icons.gps_fixed : Icons.gps_not_fixed,
              size: 64,
              color: _isGpsCalibrated ? Colors.green : Colors.orange,
            ),
            SizedBox(height: 16),
            Text(message),
            if (action.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(action, style: TextStyle(color: Colors.orange)),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showGpsGuidance() {
    if (_gpsAccuracy > 15.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Poor GPS signal (±${_gpsAccuracy.toStringAsFixed(1)}m). Move away from buildings and trees.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } else if (_gpsAccuracy > 10.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fair GPS signal (±${_gpsAccuracy.toStringAsFixed(1)}m). Consider moving to more open area.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showCalibrationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sensor Calibration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                _isMagneticCalibrated ? Icons.check_circle : Icons.warning,
                color: _isMagneticCalibrated ? Colors.green : Colors.orange,
              ),
              title: Text('Magnetic Sensor'),
              subtitle: Text(_isMagneticCalibrated ? 'Calibrated' : 'Needs calibration'),
              trailing: ElevatedButton(
                onPressed: _calibrateMagnetic,
                child: Text('Calibrate'),
              ),
            ),
            ListTile(
              leading: Icon(
                _isGpsCalibrated ? Icons.check_circle : Icons.warning,
                color: _isGpsCalibrated ? Colors.green : Colors.orange,
              ),
              title: Text('GPS Sensor'),
              subtitle: Text(_isGpsCalibrated ? 'Good signal' : 'Poor signal'),
              trailing: ElevatedButton(
                onPressed: _checkGpsQuality,
                child: Text('Check'),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  // ==================== SETTINGS ====================

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Survey Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Magnetic Pull Rate'),
                subtitle: Text('How often to collect data automatically'),
                trailing: DropdownButton<Duration>(
                  value: _magneticPullRate,
                  items: [
                    DropdownMenuItem(value: Duration(milliseconds: 500), child: Text('0.5s')),
                    DropdownMenuItem(value: Duration(seconds: 1), child: Text('1s')),
                    DropdownMenuItem(value: Duration(seconds: 2), child: Text('2s')),
                    DropdownMenuItem(value: Duration(seconds: 5), child: Text('5s')),
                    DropdownMenuItem(value: Duration(seconds: 10), child: Text('10s')),
                  ],
                  onChanged: (Duration? value) {
                    if (value != null) {
                      setState(() => _magneticPullRate = value);
                      _restartAutomaticCollection();
                    }
                  },
                ),
              ),
              Divider(),
              ListTile(
                title: Text('Base Map Layer'),
                subtitle: Text(_getBaseLayerName(_currentBaseLayer)),
                trailing: DropdownButton<MapBaseLayer>(
                  value: _currentBaseLayer,
                  items: [
                    DropdownMenuItem(value: MapBaseLayer.openStreetMap, child: Text('OpenStreetMap')),
                    DropdownMenuItem(value: MapBaseLayer.satellite, child: Text('Satellite')),
                    DropdownMenuItem(value: MapBaseLayer.emag2Magnetic, child: Text('EMAG2 Magnetic')),
                  ],
                  onChanged: (MapBaseLayer? value) {
                    if (value != null) {
                      setState(() => _currentBaseLayer = value);
                    }
                  },
                ),
              ),
              Divider(),
              SwitchListTile(
                title: Text('Show Compass'),
                subtitle: Text('Display compass overlay'),
                value: _showCompass,
                onChanged: (bool value) => setState(() => _showCompass = value),
              ),
              SwitchListTile(
                title: Text('Show Grid'),
                subtitle: Text('Display survey grid overlay'),
                value: _showGrid,
                onChanged: (bool value) => setState(() => _showGrid = value),
              ),
              SwitchListTile(
                title: Text('Team Mode'),
                subtitle: Text('Enable team collaboration'),
                value: _isTeamMode,
                onChanged: _onTeamModeToggle,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getBaseLayerName(MapBaseLayer layer) {
    switch (layer) {
      case MapBaseLayer.openStreetMap:
        return 'OpenStreetMap';
      case MapBaseLayer.satellite:
        return 'Satellite View';
      case MapBaseLayer.emag2Magnetic:
        return 'EMAG2 Global Magnetic';
    }
  }

  // ==================== DATA COLLECTION ====================

  Future<void> _recordMagneticReading() async {
    if (_currentPosition == null) return;

    if (!_isMagneticCalibrated || !_isGpsCalibrated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please calibrate sensors before collecting data'),
          action: SnackBarAction(
            label: 'Calibrate',
            onPressed: () => _showCalibrationDialog(),
          ),
        ),
      );
      return;
    }

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

      // Update current cell
      GridCell? cellContainingPoint = _gridCells.firstWhere(
        (cell) => _isPointInCell(LatLng(reading.latitude, reading.longitude), cell.bounds),
        orElse: () => _gridCells.first,
      );

      if (cellContainingPoint != null) {
        cellContainingPoint.pointCount++;
        if (cellContainingPoint.status == GridCellStatus.notStarted) {
          cellContainingPoint.status = GridCellStatus.inProgress;
          cellContainingPoint.startTime = DateTime.now();
        }
        if (cellContainingPoint.pointCount >= 5) {
          cellContainingPoint.status = GridCellStatus.completed;
          cellContainingPoint.completedTime = DateTime.now();
        }
      }

      _updateCoverageStats();
      _findNextTargetCell();
    });

    if (_isTeamMode && _currentCell != null) {
      _teamService.updateGridCell(_currentCell!);
    }
  }

  void _toggleDataCollection() {
    if (!_isMagneticCalibrated || !_isGpsCalibrated) {
      _showCalibrationDialog();
      return;
    }

    setState(() {
      _isCollecting = !_isCollecting;
      _surveyMode = _isCollecting ? 'auto' : 'manual';
    });

    if (_isCollecting) {
      _startAutomaticCollection();
    } else {
      _automaticCollectionTimer?.cancel();
    }
  }

  void _startAutomaticCollection() {
    _automaticCollectionTimer?.cancel();
    _automaticCollectionTimer = Timer.periodic(_magneticPullRate, (timer) {
      if (_isCollecting && mounted) {
        _recordMagneticReading();
      } else {
        timer.cancel();
      }
    });
  }

  void _restartAutomaticCollection() {
    if (_isCollecting) {
      _automaticCollectionTimer?.cancel();
      _startAutomaticCollection();
    }
  }

  // ==================== TEAM COLLABORATION ====================

  void _onTeamModeToggle(bool enabled) {
    setState(() {
      _isTeamMode = enabled;
    });
    
    if (enabled) {
      _showTeamSetupDialog();
    } else {
      _teamService.stopTeamMode();
    }
  }

  void _showTeamSetupDialog() {
    String userName = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Start Team Survey'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Your Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => userName = value,
            ),
            SizedBox(height: 16),
            Text(
              'Team members can join by scanning QR code or entering project ID',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _isTeamMode = false);
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _teamService.startTeamMode(userName.isEmpty ? 'User' : userName, 'project_123');
              Navigator.pop(context);
            },
            child: Text('Start Team Mode'),
          ),
        ],
      ),
    );
  }

  void _showBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => TeamPanel(onTeamModeToggle: _onTeamModeToggle),
    );
  }

  // ==================== FIELD NOTES ====================

  void _showFieldNotesDialog() {
    showDialog(
      context: context,
      builder: (context) => EnhancedFieldNotesDialog(
        onNoteSaved: (note, imagePath, audioPath) {
          _saveFieldNote(note, imagePath, audioPath);
        },
      ),
    );
  }

  Future<void> _saveFieldNote(String note, String? imagePath, String? audioPath) async {
    if (_currentPosition == null) return;

    FieldNote fieldNote = FieldNote(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      note: note,
      imagePath: imagePath,
      audioPath: audioPath,
      timestamp: DateTime.now(),
      projectId: widget.project?.id ?? 1,
    );

    if (!_isWebMode) {
      await DatabaseService.instance.insertFieldNote(fieldNote);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Field note saved successfully')),
    );
  }

  // ==================== EXPORT ====================

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
            _buildExportOption('CSV Format', 'Spreadsheet compatible', Icons.table_chart, ExportFormat.csv),
            _buildExportOption('GeoJSON', 'GIS compatible', Icons.map, ExportFormat.geojson),
            _buildExportOption('KML/Google Earth', 'View in Google Earth', Icons.public, ExportFormat.kml),
            if (!kIsWeb) ...[
              _buildExportOption('SQLite Database', 'Complete database', Icons.storage, ExportFormat.sqlite),
              _buildExportOption('Shapefile (WKT)', 'GIS shapefile format', Icons.layers, ExportFormat.shapefile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption(String title, String description, IconData icon, ExportFormat format) {
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

      SurveyProject project = widget.project ?? SurveyProject(
        name: 'Current Survey',
        description: 'Magnetic survey data',
        createdAt: DateTime.now(),
      );

      List<MagneticReading> allReadings = [];
      List<FieldNote> fieldNotes = [];

      if (!_isWebMode && widget.project?.id != null) {
        allReadings = await DatabaseService.instance.getReadingsForProject(widget.project!.id!);
      }

      String exportData = await _exportService.exportProject(
        project: project,
        readings: allReadings,
        gridCells: _gridCells,
        fieldNotes: fieldNotes,
        format: format,
      );

      Navigator.pop(context);

      String filename = '${project.name}_${DateTime.now().millisecondsSinceEpoch}${_exportService.getFileExtension(format)}';
      String mimeType = _exportService.getMimeType(format);

      await _exportService.saveAndShare(
        data: exportData,
        filename: filename,
        mimeType: mimeType,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data exported successfully as $filename')),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  // ==================== UI COMPONENTS ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Survey - ${widget.project?.name ?? 'Default'}'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _showSettings,
          ),
          IconButton(
            icon: Icon(Icons.tune),
            onPressed: _showCalibrationDialog,
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
          Expanded(flex: 3, child: _buildMapView()),
          _buildControlPanel(),
        ],
      ),
      bottomSheet: _isTeamMode ? TeamPanel(onTeamModeToggle: _onTeamModeToggle) : null,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_isTeamMode)
            FloatingActionButton(
              heroTag: "team",
              onPressed: _showBottomSheet,
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatusItem('Coverage', '${_coveragePercentage.toStringAsFixed(0)}%', 
                _coveragePercentage > 75 ? Colors.green : _coveragePercentage > 25 ? Colors.orange : Colors.red),
            SizedBox(width: 16),
            _buildStatusItem('Points', '$_pointCount', Colors.blue),
            SizedBox(width: 16),
            _buildStatusItem('Field', '${_totalField.toStringAsFixed(0)} μT', Colors.purple),
            SizedBox(width: 16),
            _buildStatusItem('Mode', _surveyMode.toUpperCase(), _isCollecting ? Colors.green : Colors.grey),
            if (_isTeamMode) ...[
              SizedBox(width: 16),
              _buildStatusItem('Team', '${_teamMembers.length}', Colors.orange),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

Widget _buildMapView() {
  return Stack(
    children: [
      FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          // FIXED: Changed 'center' to 'initialCenter'
          initialCenter: _currentPosition != null 
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
              : LatLng(5.6037, -0.1870),
          // FIXED: Changed 'zoom' to 'initialZoom' 
          initialZoom: 18.0,
          maxZoom: 20.0,
          minZoom: 10.0,
          // REMOVED: backgroundColor is no longer supported in MapOptions
          // Use Container wrapper instead if needed
        ),
        children: [
          // Your existing map layers...
          _buildBaseMapLayer(),
          
          // Rest of your map layers remain the same
          if (_showGrid)
            PolygonLayer(
              polygons: _gridCells.map((cell) => Polygon(
                points: cell.bounds,
                color: _getCellColor(cell.status).withOpacity(0.2),
                borderColor: _getCellColor(cell.status),
                borderStrokeWidth: 2.0,
              )).toList(),
            ),
          
          // Previous survey points
          if (_savedReadings.isNotEmpty)
            CircleLayer(
              circles: _savedReadings.map((reading) => CircleMarker(
                point: LatLng(reading.latitude, reading.longitude),
                radius: 3,
                color: Colors.blue,
                borderColor: Colors.white,
                borderStrokeWidth: 1,
              )).toList(),
            ),
          
          // Current session points
          CircleLayer(
            circles: _collectedPoints.map((point) => CircleMarker(
              point: point,
              radius: 4,
              color: Colors.green,
              borderColor: Colors.white,
              borderStrokeWidth: 1,
            )).toList(),
          ),
          
          // Team members positions
          if (_showTeamMembers && _isTeamMode)
            MarkerLayer(
              markers: _teamMembers
                  .where((member) => member.currentPosition != null && member.id != _teamService.currentUserId)
                  .map((member) => Marker(
                    point: member.currentPosition!,
                    width: 25,
                    height: 25,
                    child: Transform.rotate(
                      angle: (member.heading ?? 0) * math.pi / 180,
                      child: Container(
                        decoration: BoxDecoration(
                          color: member.markerColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(Icons.person, color: Colors.white, size: 16),
                      ),
                    ),
                  )).toList(),
            ),
          
          // Current position with heading
          if (_currentPosition != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  width: 30,
                  height: 30,
                  child: Transform.rotate(
                    angle: (_heading ?? 0) * math.pi / 180,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isGpsCalibrated ? Colors.green : Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(Icons.navigation, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      
      // Compass overlay
      if (_showCompass)
        Positioned(
          top: 16,
          right: 16,
          child: _buildCompassWidget(),
        ),
        
      // GPS status
      Positioned(
        bottom: 16,
        right: 16,
        child: _buildGpsStatusWidget(),
      ),
      
      // ADDED: Calibration status indicator that was missing
      Positioned(
        bottom: 16,
        left: 16,
        child: _buildCalibrationStatusWidget(),
      ),
    ],
  );
}

  Widget _buildBaseMapLayer() {
    switch (_currentBaseLayer) {
      case MapBaseLayer.openStreetMap:
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.magnetic_survey_app',
        );
      case MapBaseLayer.satellite:
        return TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.example.magnetic_survey_app',
        );
      case MapBaseLayer.emag2Magnetic:
        return TileLayer(
          urlTemplate: 'https://geocloud.radiantearth.io/api/v1/mosaic/emag2-magnetic-anomaly/tiles/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.magnetic_survey_app',
          //backgroundColor: Colors.transparent,
        );
    }
  }

  Widget _buildCompassWidget() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Transform.rotate(
        angle: -(_heading ?? 0) * math.pi / 180,
        child: CustomPaint(
          painter: CompassPainter(),
          size: Size(80, 80),
        ),
      ),
    );
  }

  Widget _buildGpsStatusWidget() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isGpsCalibrated ? Colors.green : Colors.orange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isGpsCalibrated ? Icons.gps_fixed : Icons.gps_not_fixed,
            color: Colors.white,
            size: 16,
          ),
          SizedBox(width: 4),
          Text(
            '±${_gpsAccuracy.toStringAsFixed(1)}m',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrationStatusWidget() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (_isMagneticCalibrated && _isGpsCalibrated) ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            (_isMagneticCalibrated && _isGpsCalibrated) ? Icons.check_circle : Icons.warning,
            color: Colors.white,
            size: 16,
          ),
          SizedBox(width: 4),
          Text(
            (_isMagneticCalibrated && _isGpsCalibrated) ? 'Calibrated' : 'Need Calibration',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                  onPressed: () => setState(() => _showCompass = !_showCompass),
                  icon: Icon(_showCompass ? Icons.explore_off : Icons.explore),
                  label: Text(_showCompass ? 'Hide Compass' : 'Show Compass'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _showCompass ? Colors.blue : Colors.grey,
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
                    onPressed: () => setState(() => _showTeamMembers = !_showTeamMembers),
                    icon: Icon(_showTeamMembers ? Icons.group_off : Icons.group),
                    label: Text(_showTeamMembers ? 'Hide Team' : 'Show Team'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _showTeamMembers ? Colors.purple : Colors.grey,
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

  // ==================== HELPER METHODS ====================

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

  bool _isPointInCell(LatLng point, List<LatLng> bounds) {
    double minLat = bounds.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = bounds.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLon = bounds.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLon = bounds.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

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
    int completed = _gridCells.where((cell) => cell.status == GridCellStatus.completed).length;
    setState(() {
      _completedCells = completed;
      _coveragePercentage = (completed / _gridCells.length) * 100;
    });
  }
}

// ==================== ENHANCED FIELD NOTES DIALOG ====================

class EnhancedFieldNotesDialog extends StatefulWidget {
  final Function(String, String?, String?) onNoteSaved;

  EnhancedFieldNotesDialog({required this.onNoteSaved});

  @override
  _EnhancedFieldNotesDialogState createState() => _EnhancedFieldNotesDialogState();
}

class _EnhancedFieldNotesDialogState extends State<EnhancedFieldNotesDialog> {
  final _noteController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isRecording = false;
  String? _imagePath;
  Uint8List? _imageBytes;
  String? _audioPath;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.note_add, color: Colors.blue),
          SizedBox(width: 8),
          Text('Field Notes'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: 'Add field observation...',
                border: OutlineInputBorder(),
                hintText: 'Describe geological features, anomalies, or conditions',
              ),
              maxLines: 4,
              maxLength: 500,
            ),
            SizedBox(height: 16),
            
            // Show attached media
            if (_imagePath != null && (kIsWeb ? _imageBytes != null : _imagePath!.isNotEmpty)) ...[
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.memory(
                              _imageBytes!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 100,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey[200],
                                child: Center(child: Text('Failed to load image')),
                              ),
                            )
                          : Image(
                              image: FileImage(io.File(_imagePath!)),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 100,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey[200],
                                child: Center(child: Text('Failed to load image')),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _imagePath = null;
                          _imageBytes = null;
                        }),
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
            ],
            
            if (_audioPath != null) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    Icon(Icons.audiotrack, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(child: Text('Audio recording attached')),
                    GestureDetector(
                      onTap: () => setState(() => _audioPath = null),
                      child: Icon(Icons.close, color: Colors.red),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
            ],
            
            // Media options
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _takePhoto,
                  icon: Icon(Icons.camera_alt),
                  label: Text('Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _selectFromGallery,
                  icon: Icon(Icons.photo_library),
                  label: Text('Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _toggleRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? 'Stop' : 'Voice'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveNote,
          child: Text('Save Note'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image != null) {
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          setState(() {
            _imagePath = image.path;
            _imageBytes = bytes;
          });
        } else {
          setState(() {
            _imagePath = image.path;
            _imageBytes = null;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo captured successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to take photo: $e')),
      );
    }
  }

  Future<void> _selectFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image != null) {
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          setState(() {
            _imagePath = image.path;
            _imageBytes = bytes;
          });
        } else {
          setState(() {
            _imagePath = image.path;
            _imageBytes = null;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image selected successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to select image: $e')),
      );
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording started...')),
      );
      Future.delayed(Duration(seconds: 2), () {
        if (_isRecording && mounted) {
          setState(() {
            _audioPath = 'audio_${DateTime.now().millisecondsSinceEpoch}.wav';
            _isRecording = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Recording completed')),
          );
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording stopped')),
      );
    }
  }

  void _saveNote() {
    if (_noteController.text.trim().isEmpty && _imagePath == null && _audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a note or attach media')),
      );
      return;
    }

    widget.onNoteSaved(_noteController.text.trim(), _imagePath, _audioPath);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }
}

// ==================== COMPASS PAINTER ====================

class CompassPainter extends CustomPainter {
  @override
  void paint(ui.Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Draw compass circle
    final circlePaint = ui.Paint()
      ..color = Colors.white
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(center, radius, circlePaint);

    // Draw border
    final borderPaint = ui.Paint()
      ..color = Colors.black
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw north indicator (red arrow)
    final northPaint = ui.Paint()
      ..color = Colors.red
      ..style = ui.PaintingStyle.fill;
    
    final northPath = ui.Path();
    northPath.moveTo(center.dx, center.dy - radius + 8);
    northPath.lineTo(center.dx - 4, center.dy - radius + 20);
    northPath.lineTo(center.dx + 4, center.dy - radius + 20);
    northPath.close();
    canvas.drawPath(northPath, northPaint);

    // Draw south indicator (white arrow)
    final southPaint = ui.Paint()
      ..color = Colors.grey
      ..style = ui.PaintingStyle.fill;
    
    final southPath = ui.Path();
    southPath.moveTo(center.dx, center.dy + radius - 8);
    southPath.lineTo(center.dx - 4, center.dy + radius - 20);
    southPath.lineTo(center.dx + 4, center.dy + radius - 20);
    southPath.close();
    canvas.drawPath(southPath, southPaint);

    // Draw 'N' text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - 6, center.dy - radius + 22));

    // Draw cardinal direction marks
    final markPaint = ui.Paint()
      ..color = Colors.black
      ..strokeWidth = 1;

    // E, S, W marks
    List<String> directions = ['E', 'S', 'W'];
    for (int i = 1; i < 4; i++) {
      double angle = i * math.pi / 2;
      double x1 = center.dx + (radius - 8) * math.cos(angle - math.pi / 2);
      double y1 = center.dy + (radius - 8) * math.sin(angle - math.pi / 2);
      double x2 = center.dx + (radius - 15) * math.cos(angle - math.pi / 2);
      double y2 = center.dy + (radius - 15) * math.sin(angle - math.pi / 2);
      
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), markPaint);
      
      // Draw direction letters
      final directionPainter = TextPainter(
        text: TextSpan(
          text: directions[i - 1],
          style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      directionPainter.layout();
      directionPainter.paint(canvas, Offset(x2 - 5, y2 - 5));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}