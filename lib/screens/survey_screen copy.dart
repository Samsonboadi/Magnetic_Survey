// lib/screens/survey_screen.dart
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

// Define MapBaseLayer enum
enum MapBaseLayer {
  openStreetMap,
  satellite,
  emag2Magnetic,
}

class SurveyScreen extends StatefulWidget {
  final SurveyProject? project;
  final List<GridCell>? initialGridCells;
  final LatLng? gridCenter;

  SurveyScreen({
    this.project,
    this.initialGridCells,
    this.gridCenter,
  });

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
  Timer? _webSimulationTimer;

  // Stream subscriptions
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<TeamMember>>? _teamSyncSubscription;

  // Services
  final TeamSyncService _teamService = TeamSyncService.instance;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _startSensorListening();
    _setupTeamSync();
    
    // Only load grid if passed from grid management
    if (widget.initialGridCells != null && widget.initialGridCells!.isNotEmpty) {
      setState(() {
        _gridCells = widget.initialGridCells!;
        _showGrid = true;
      });
      _findNextTargetCell();
    }
    
    _loadPreviousSurveyData();
    
    if (_isWebMode) {
      _simulateDataForWeb();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _compassSubscription?.cancel();
    _teamSyncSubscription?.cancel();
    _automaticCollectionTimer?.cancel();
    _webSimulationTimer?.cancel();
    super.dispose();
  }

  // ==================== INITIALIZATION ====================

  void _setupTeamSync() {
    _teamSyncSubscription = _teamService.teamMembersStream.listen((members) {
      if (mounted) {
        setState(() {
          _teamMembers = members;
          _isTeamMode = members.isNotEmpty;
        });
      }
    });
  }

  Future<void> _loadPreviousSurveyData() async {
    if (widget.project != null && !_isWebMode) {
      try {
        final readings = await DatabaseService.instance.getReadingsForProject(widget.project!.id!);
        if (mounted) {
          setState(() {
            _savedReadings = readings;
            _collectedPoints.addAll(readings.map((r) => LatLng(r.latitude, r.longitude)));
            _pointCount = readings.length;
          });
          _updateCoverageStats();
        }
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
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        );
        
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _gpsAccuracy = position.accuracy;
            _isGpsCalibrated = position.accuracy < 5.0;
          });
          
          // Center the map on current location
          _mapController.move(
            LatLng(position.latitude, position.longitude), 
            18.0
          );
        }
        
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1,
          ),
        ).listen((Position position) {
          if (mounted) {
            setState(() {
              _currentPosition = position;
              _gpsAccuracy = position.accuracy;
              if (position.accuracy > 10.0) {
                _showGpsGuidance();
              }
            });
            
            // Auto-center map on location updates if needed
            if (_autoNavigate) {
              _mapController.move(
                LatLng(position.latitude, position.longitude), 
                _mapController.camera.zoom
              );
            }
            
            if (_isTeamMode) {
              _teamService.updateMyPosition(
                LatLng(position.latitude, position.longitude), 
                _heading
              );
            }
          }
        });
      }
    } catch (e) {
      print('Location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to get current location. Please check GPS and permissions.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startSensorListening() {
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      if (mounted) {
        setState(() {
          _magneticX = event.x - _magneticCalibrationX;
          _magneticY = event.y - _magneticCalibrationY;
          _magneticZ = event.z - _magneticCalibrationZ;
          _totalField = SensorService.calculateTotalField(_magneticX, _magneticY, _magneticZ);
        });
      }
    });

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted) {
        setState(() {
          _heading = event.heading;
        });
      }
    });
  }

  void _simulateDataForWeb() {
    _webSimulationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
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

  void _showGpsGuidance() {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'GPS accuracy is poor. Move to open sky for better signal.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ==================== GRID MANAGEMENT ====================

  void _findNextTargetCell() {
    if (_gridCells.isEmpty) return;

    GridCell? nextCell;
    for (var cell in _gridCells) {
      if (cell.status == GridCellStatus.notStarted) {
        nextCell = cell;
        break;
      }
    }

    if (nextCell == null) {
      for (var cell in _gridCells) {
        if (cell.status == GridCellStatus.inProgress) {
          nextCell = cell;
          break;
        }
      }
    }

    setState(() {
      _nextTargetCell = nextCell;
    });

    if (nextCell != null && _autoNavigate) {
      _mapController.move(
        LatLng(nextCell.centerLat, nextCell.centerLon),
        _mapController.camera.zoom
      );
    }
  }

  void _updateCoverageStats() {
    if (_gridCells.isNotEmpty) {
      _completedCells = _gridCells.where((cell) => cell.status == GridCellStatus.completed).length;
      _coveragePercentage = (_completedCells / _gridCells.length) * 100;
    } else {
      _completedCells = 0;
      _coveragePercentage = 0.0;
    }
    
    // Update point count from actual collected points + saved readings
    _pointCount = _collectedPoints.length + _savedReadings.length;
  }

  Color _getCellColor(GridCellStatus status) {
    switch (status) {
      case GridCellStatus.notStarted:
        return Colors.grey;
      case GridCellStatus.inProgress:
        return Colors.orange;
      case GridCellStatus.completed:
        return Colors.green;
    }
  }

  // ==================== UI COMPONENTS ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.project?.name ?? 'Survey Session',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Points: $_pointCount | Coverage: ${_coveragePercentage.toStringAsFixed(1)}% | Field: ${_totalField.toStringAsFixed(1)}nT',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _showSettings,
          ),
          IconButton(
            icon: Icon(Icons.help),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControlPanel(),
          Expanded(child: _buildMapView()),
        ],
      ),
      bottomNavigationBar: _buildBottomStatsBar(),
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : LatLng(5.6037, -0.1870),
            initialZoom: 18.0,
            maxZoom: 20.0,
            minZoom: 10.0,
          ),
          children: [
            _buildBaseMapLayer(),
            if (_showGrid && _gridCells.isNotEmpty)
              PolygonLayer(
                polygons: _gridCells.map((cell) => Polygon(
                  points: cell.bounds,
                  color: _getCellColor(cell.status).withOpacity(0.2),
                  borderColor: _getCellColor(cell.status),
                  borderStrokeWidth: 2.0,
                )).toList(),
              ),
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
            CircleLayer(
              circles: _collectedPoints.map((point) => CircleMarker(
                point: point,
                radius: 4,
                color: Colors.green,
                borderColor: Colors.white,
                borderStrokeWidth: 1,
              )).toList(),
            ),
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
        
        // COMPASS - Top right (only show if enabled)
        if (_showCompass)
          Positioned(
            top: 16,
            right: 16,
            child: _buildCompassWidget(),
          ),
        
        // GPS STATUS - Bottom right
        Positioned(
          bottom: 100, // Move up to avoid floating buttons
          right: 16,
          child: _buildGpsStatusWidget(),
        ),
        
        // CALIBRATION STATUS - Bottom left  
        Positioned(
          bottom: 100, // Move up to avoid floating buttons
          left: 16,
          child: _buildCalibrationStatusWidget(),
        ),
        
        // FLOATING ACTION BUTTONS - Better positioning
        Positioned(
          bottom: 20, // Standard FAB position
          right: 20,  // Standard FAB position
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Manual Recording Button
              FloatingActionButton(
                heroTag: "manual_record",
                onPressed: _recordMagneticReading,
                backgroundColor: Colors.green,
                child: Icon(Icons.add_location, color: Colors.white),
                tooltip: 'Record Point',
              ),
              
              SizedBox(height: 12), // Space between buttons
              
              // Auto Recording Toggle Button
              FloatingActionButton(
                heroTag: "auto_record",
                onPressed: _toggleAutomaticCollection,
                backgroundColor: _isCollecting ? Colors.red : Colors.blue,
                child: Icon(
                  _isCollecting ? Icons.stop : Icons.play_arrow, 
                  color: Colors.white
                ),
                tooltip: _isCollecting ? 'Stop Auto Recording' : 'Start Auto Recording',
              ),
              
              SizedBox(height: 12), // Space between buttons
              
              // Compass Toggle Button (moved here, smaller)
              FloatingActionButton.small(
                heroTag: "compass_toggle",
                onPressed: () => setState(() => _showCompass = !_showCompass),
                backgroundColor: _showCompass ? Colors.purple : Colors.grey,
                child: Icon(
                  _showCompass ? Icons.explore_off : Icons.explore, 
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: _showCompass ? 'Hide Compass' : 'Show Compass',
              ),
            ],
          ),
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
          urlTemplate: 'https://maps.ngdc.noaa.gov/arcgis/rest/services/web_mercator/emag2_magnetic_anomaly/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.example.magnetic_survey_app',
          additionalOptions: {
            'transparent': 'true',
          },
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
          painter: SurveyCompassPainter(),
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
                  onPressed: _showCalibrationDialog,
                  icon: Icon(Icons.settings_input_component),
                  label: Text('Calibrate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_isMagneticCalibrated && _isGpsCalibrated) ? Colors.green : Colors.orange,
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

  // Add bottom stats bar
  Widget _buildBottomStatsBar() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem('Points', _pointCount.toString(), Icons.location_on),
          _buildStatItem('Coverage', '${_coveragePercentage.toStringAsFixed(1)}%', Icons.grid_on),
          _buildStatItem('Field', '${_totalField.toStringAsFixed(1)}nT', Icons.sensors),
          _buildStatItem('Accuracy', '±${_gpsAccuracy.toStringAsFixed(1)}m', Icons.gps_fixed),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
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
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Magnetic sensors calibrated!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text('Calibrate'),
          ),
        ],
      ),
    );
  }

  void _checkGpsQuality() {
    if (_currentPosition != null) {
      setState(() {
        _isGpsCalibrated = _gpsAccuracy < 5.0;
      });
      
      String message = _isGpsCalibrated 
          ? 'GPS signal is good (±${_gpsAccuracy.toStringAsFixed(1)}m)'
          : 'GPS signal is poor (±${_gpsAccuracy.toStringAsFixed(1)}m). Move to open sky.';
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: _isGpsCalibrated ? Colors.green : Colors.orange,
          ),
        );
      }
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
              title: Text('Magnetometer'),
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

  void _onTeamModeToggle(bool value) {
    setState(() {
      _isTeamMode = value;
    });
    
    if (value) {
      // Enable team mode - start team sync if available
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Team mode enabled. Share session code with team members.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      // Disable team mode
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Team mode disabled.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ==================== DATA COLLECTION ====================

  Future<void> _recordMagneticReading() async {
    if (_currentPosition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Waiting for GPS location...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (!_isMagneticCalibrated || !_isGpsCalibrated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please calibrate sensors before collecting data'),
            action: SnackBarAction(
              label: 'Calibrate',
              onPressed: () => _showCalibrationDialog(),
            ),
          ),
        );
      }
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
      try {
        await DatabaseService.instance.insertMagneticReading(reading);
      } catch (e) {
        print('Error saving reading: $e');
      }
    }

    if (mounted) {
      setState(() {
        _collectedPoints.add(LatLng(reading.latitude, reading.longitude));
        _pointCount = _collectedPoints.length + _savedReadings.length;
      });
      
      // Update coverage stats immediately
      _updateCoverageStats();
      
      // Update current cell if in grid mode
      if (_currentCell != null) {
        setState(() {
          _currentCell!.pointCount++;
          if (_currentCell!.pointCount >= 1) {
            _currentCell!.status = GridCellStatus.completed;
          }
        });
      }

      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Point recorded! Total: $_pointCount'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );

      // Auto-navigate to next target if enabled
      if (_autoNavigate && _gridCells.isNotEmpty) {
        _findNextTargetCell();
      }
    }
  }

  void _toggleAutomaticCollection() {
    setState(() {
      _isCollecting = !_isCollecting;
    });

    if (_isCollecting) {
      _startAutomaticCollection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Automatic data collection started'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      _stopAutomaticCollection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Automatic data collection stopped'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _startAutomaticCollection() {
    _automaticCollectionTimer = Timer.periodic(_magneticPullRate, (timer) {
      if (!_isCollecting) {
        timer.cancel();
        return;
      }
      _recordMagneticReading();
    });
  }

  void _stopAutomaticCollection() {
    _automaticCollectionTimer?.cancel();
    _automaticCollectionTimer = null;
  }

  void _restartAutomaticCollection() {
    if (_isCollecting) {
      _stopAutomaticCollection();
      _startAutomaticCollection();
    }
  }

  // ==================== TEAM FUNCTIONALITY ====================

  void _showBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Team Panel',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _teamMembers.length,
                  itemBuilder: (context, index) {
                    final member = _teamMembers[index];
                    return ListTile(
                      leading: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: member.markerColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(member.name),
                      subtitle: Text(member.isOnline ? 'Online' : 'Offline'),
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _removeTeamMember(member),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _inviteTeamMember,
                icon: Icon(Icons.person_add),
                label: Text('Invite Team Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _inviteTeamMember() {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController emailController = TextEditingController();
        return AlertDialog(
          title: Text('Invite Team Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'Enter team member email',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 16),
              Text(
                'Session Code: SURVEY-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (emailController.text.isNotEmpty) {
                  Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Invitation sent to ${emailController.text}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: Text('Send Invite'),
            ),
          ],
        );
      },
    );
  }

  void _removeTeamMember(TeamMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Team Member'),
        content: Text('Remove ${member.name} from the survey team?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _teamMembers.remove(member);
              });
              Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${member.name} removed from team'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==================== HELP & EXPORT ====================

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Survey Help'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Getting Started:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. Calibrate sensors using the calibrate button'),
              Text('2. Wait for good GPS signal (green status)'),
              Text('3. Use manual recording or start automatic mode'),
              SizedBox(height: 16),
              Text('Recording Data:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Green FAB: Record single point'),
              Text('• Blue FAB: Start/stop automatic recording'),
              Text('• Purple FAB: Toggle compass display'),
              SizedBox(height: 16),
              Text('Map Controls:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Pinch to zoom in/out'),
              Text('• Drag to move map'),
              Text('• Grid shows survey boundaries'),
              Text('• Green dots show recorded points'),
              SizedBox(height: 16),
              Text('Team Mode:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Enable in settings to collaborate'),
              Text('• Share session code with team'),
              Text('• See team members on map'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got It'),
          ),
        ],
      ),
    );
  }

  void _exportSurveyData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Export Survey Data'),
        content: Text('Choose export format for your survey data:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              
              navigator.pop();
              try {
                // Create a project for export (use existing or create temporary)
                final project = widget.project ?? SurveyProject(
                  name: 'Survey Export',
                  description: 'Magnetic survey data export',
                  createdAt: DateTime.now(),
                );

                // Get all readings (combine collected and saved)
                List<MagneticReading> allReadings = List.from(_savedReadings);
                
                // Convert collected points to readings if needed
                for (int i = 0; i < _collectedPoints.length; i++) {
                  final point = _collectedPoints[i];
                  allReadings.add(MagneticReading(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: 0.0,
                    magneticX: _magneticX,
                    magneticY: _magneticY,
                    magneticZ: _magneticZ,
                    totalField: _totalField,
                    timestamp: DateTime.now().subtract(Duration(minutes: i)),
                    projectId: project.id ?? 1,
                  ));
                }

                // Export using ExportService
                String exportData = await ExportService.instance.exportProject(
                  project: project,
                  readings: allReadings,
                  gridCells: _gridCells,
                  fieldNotes: [], // Empty field notes for now
                  format: ExportFormat.csv,
                );

                // Generate filename
                String filename = '${project.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
                
                // Save and share
                await ExportService.instance.saveAndShare(
                  data: exportData,
                  filename: filename,
                  mimeType: 'text/csv',
                );

                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Data exported to $filename'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Export failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text('Export CSV'),
          ),
        ],
      ),
    );
  }
}

// ==================== COMPASS PAINTER ====================

class SurveyCompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Draw compass circle
    final circlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, circlePaint);

    final borderPaint = Paint()
      ..color = Colors.grey[400]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw north arrow
    final arrowPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    final path = ui.Path();
    path.moveTo(center.dx, center.dy - radius + 5);
    path.lineTo(center.dx - 8, center.dy - 5);
    path.lineTo(center.dx + 8, center.dy - 5);
    path.close();
    canvas.drawPath(path, arrowPaint);

    // Draw N label
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.red,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + 10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}