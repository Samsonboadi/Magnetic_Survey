// Fixed Survey Screen - Original UI with Grid Projection Fix
// File: lib/screens/survey_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;


import 'dart:io';
import 'package:share_plus/share_plus.dart';


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

class _SurveyScreenState extends State<SurveyScreen> with TickerProviderStateMixin {
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
  bool _hasLocationError = false;
  bool _needsTargetCellUpdate = false;
  bool _isMapReady = false;
  String _surveyMode = 'manual';
  MapBaseLayer _currentBaseLayer = MapBaseLayer.openStreetMap;

  // Settings
  Duration _magneticPullRate = Duration(seconds: 1);
  Timer? _automaticCollectionTimer;
  Timer? _webSimulationTimer;
  Timer? _mapInitializationTimer;

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

    // FIX: Initialize map and grid with proper timing
    _initializeMapWithDelay();

    _loadPreviousSurveyData();
    
    if (_isWebMode) {
      _simulateDataForWeb();
    }
  }


  void _initializeMapWithDelay() {
    _mapInitializationTimer = Timer(Duration(milliseconds: 500), () {
      setState(() {
        _isMapReady = true;
      });
      
      // If we have current position, center map on it
      if (_currentPosition != null) {
        _centerOnCurrentLocation();
      }
      
      // Load grid if passed from grid management
      if (widget.initialGridCells != null && widget.initialGridCells!.isNotEmpty) {
        setState(() {
          _gridCells = widget.initialGridCells!;
          _showGrid = true;
        });
        
        // If no current position, center on grid
        if (_currentPosition == null && widget.gridCenter != null) {
          _mapController.move(widget.gridCenter!, 16.0);
        }
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _compassSubscription?.cancel();
    _teamSyncSubscription?.cancel();
    _automaticCollectionTimer?.cancel();
    _webSimulationTimer?.cancel();
    _mapInitializationTimer?.cancel();
    super.dispose();
  }



  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Show location error after widget tree is fully built
    if (_hasLocationError) {
      _hasLocationError = false; // Reset flag
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to get current location. Please check GPS and permissions.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    }

    // Update target cell after map is ready and grid is loaded
    if (_needsTargetCellUpdate && _isMapReady) {
      _needsTargetCellUpdate = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _gridCells.isNotEmpty) {
          _findNextTargetCell();
        }
      });
    }
  }

  // FIX: Improved grid center navigation with retry mechanism
  void _navigateToGridCenterWithRetry() {
    if (widget.gridCenter == null) return;

    // Try multiple times with increasing delays
    List<int> delays = [100, 500, 1000, 2000];
    
    void attemptNavigation(int attemptIndex) {
      if (attemptIndex >= delays.length) {
        print('Failed to navigate to grid center after all attempts');
        return;
      }

      Timer(Duration(milliseconds: delays[attemptIndex]), () {
        if (mounted && _mapController.mapEventStream != null) {
          try {
            print('Attempting navigation to grid center: ${widget.gridCenter}');
            
            // Calculate proper zoom level based on grid size
            double zoom = _calculateOptimalZoom();
            
            _mapController.move(widget.gridCenter!, zoom);
            print('Navigation successful on attempt ${attemptIndex + 1}');
            
            // Verify the move was successful after a short delay
            Timer(Duration(milliseconds: 300), () {
              if (_mapController.camera.center.latitude.toStringAsFixed(4) != 
                  widget.gridCenter!.latitude.toStringAsFixed(4)) {
                print('Navigation verification failed, retrying...');
                attemptNavigation(attemptIndex + 1);
              } else {
                print('Navigation verified successful');
              }
            });
            
          } catch (e) {
            print('Navigation attempt ${attemptIndex + 1} failed: $e');
            attemptNavigation(attemptIndex + 1);
          }
        } else {
          print('Map controller not ready, retrying...');
          attemptNavigation(attemptIndex + 1);
        }
      });
    }

    attemptNavigation(0);
  }

  // FIX: Calculate optimal zoom level based on grid extent
  double _calculateOptimalZoom() {
    if (_gridCells.isEmpty) return 16.0;

    // Calculate grid bounds
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (var cell in _gridCells) {
      for (var point in cell.bounds) {
        minLat = math.min(minLat, point.latitude);
        maxLat = math.max(maxLat, point.latitude);
        minLng = math.min(minLng, point.longitude);
        maxLng = math.max(maxLng, point.longitude);
      }
    }

    // Calculate distance in degrees
    double latDistance = maxLat - minLat;
    double lngDistance = maxLng - minLng;
    double maxDistance = math.max(latDistance, lngDistance);

    // Convert to approximate zoom level
    if (maxDistance > 0.01) return 12.0;       // > ~1km
    else if (maxDistance > 0.005) return 13.0;  // > ~500m
    else if (maxDistance > 0.002) return 14.0;  // > ~200m
    else if (maxDistance > 0.001) return 15.0;  // > ~100m
    else if (maxDistance > 0.0005) return 16.0; // > ~50m
    else return 17.0;                           // < 50m
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
          });
          _updateCoverageStats();
        }
      } catch (e) {
        print('Error loading previous survey data: $e');
      }
    }
  }

  Future<void> _initializeLocation() async {
    if (kIsWeb) {
      // FIX: For web, prioritize grid center, then try to get actual location, then use intelligent default
      if (widget.gridCenter != null) {
        // Use grid center location for web mode
        setState(() {
          _currentPosition = Position(
            latitude: widget.gridCenter!.latitude,
            longitude: widget.gridCenter!.longitude,
            timestamp: DateTime.now(),
            accuracy: 5.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
          _isGpsCalibrated = true;
          _gpsAccuracy = 5.0;
        });
        return;
      }

      // Try to get actual web location if grid center not available
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        );
        
        setState(() {
          _currentPosition = position;
          _isGpsCalibrated = true;
          _gpsAccuracy = position.accuracy;
        });
        return;
      } catch (e) {
        print('Web location failed: $e');
        // Fall back to a reasonable default (user's approximate region based on time zone or other hints)
        // For now, use a neutral location
        setState(() {
          _currentPosition = Position(
            latitude: 0.0,  // Equator
            longitude: 0.0, // Prime Meridian
            timestamp: DateTime.now(),
            accuracy: 1000.0, // Large accuracy to indicate it's a fallback
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
          _isGpsCalibrated = false;
          _gpsAccuracy = 1000.0;
        });
      }
      return;
    }

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _hasLocationError = true);
          _useGridCenterAsFallback();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _hasLocationError = true);
        _useGridCenterAsFallback();
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _gpsAccuracy = position.accuracy;
          _isGpsCalibrated = position.accuracy < 10.0;
        });

        // Start position stream for continuous updates
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 1,  // Update every 1 meter
          ),
        ).listen((Position position) {
          if (mounted) {
            setState(() {
              _currentPosition = position;
              _gpsAccuracy = position.accuracy;
              _isGpsCalibrated = position.accuracy < 10.0;
            });

            // Update current cell based on position
            _updateCurrentCell();
          }
        });
      }
    } catch (e) {
      print('Location initialization error: $e');
      setState(() => _hasLocationError = true);
      _useGridCenterAsFallback();
    }
  }

  // FIX: New fallback method for when GPS fails
  void _useGridCenterAsFallback() {
    if (widget.gridCenter != null) {
      setState(() {
        _currentPosition = Position(
          latitude: widget.gridCenter!.latitude,
          longitude: widget.gridCenter!.longitude,
          timestamp: DateTime.now(),
          accuracy: 1000.0, // Large accuracy to indicate it's a fallback
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
        _isGpsCalibrated = false;
        _gpsAccuracy = 1000.0;
      });
    }
  }

  void _startSensorListening() {
    if (_isWebMode) {
      return;
    }

    // Listen to magnetometer
    _magnetometerSubscription = magnetometerEvents.listen(
      (MagnetometerEvent event) {
        if (mounted) {
          setState(() {
            _magneticX = event.x - _magneticCalibrationX;
            _magneticY = event.y - _magneticCalibrationY;
            _magneticZ = event.z - _magneticCalibrationZ;
            _totalField = math.sqrt(_magneticX * _magneticX + _magneticY * _magneticY + _magneticZ * _magneticZ);
            _isMagneticCalibrated = _totalField > 10.0;
          });
        }
      },
    );

    // Listen to compass
    _compassSubscription = FlutterCompass.events?.listen(
      (CompassEvent event) {
        if (mounted && event.heading != null) {
          setState(() {
            _heading = event.heading;
          });
        }
      },
    );
  }

  void _simulateDataForWeb() {
    _webSimulationTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _magneticX = -15.0 + (math.Random().nextDouble() * 30.0);
          _magneticY = -15.0 + (math.Random().nextDouble() * 30.0);
          _magneticZ = 25.0 + (math.Random().nextDouble() * 20.0);
          _totalField = math.sqrt(_magneticX * _magneticX + _magneticY * _magneticY + _magneticZ * _magneticZ);
          _isMagneticCalibrated = true;
          _heading = math.Random().nextDouble() * 360.0;
        });
      }
    });
  }




// ======================Record magnetic reading======================

void _recordMagneticReading() {
  if (_currentPosition == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No GPS location available'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  // Create reading with proper GPS data
  final reading = MagneticReading(
    projectId: widget.project?.id ?? 1,
    latitude: _currentPosition!.latitude,
    longitude: _currentPosition!.longitude,
    altitude: _currentPosition!.altitude, // FIX: Use actual altitude from GPS
    magneticX: _magneticX,
    magneticY: _magneticY,
    magneticZ: _magneticZ,
    totalField: _totalField,
    timestamp: DateTime.now(),
    accuracy: _currentPosition!.accuracy, // FIX: Use actual GPS accuracy
    heading: _heading, // FIX: Use actual compass heading
    notes: 'Auto collection',
  );

  // Save to database if not in web mode
  if (!_isWebMode && widget.project != null) {
    DatabaseService.instance.insertMagneticReading(reading);
  }

  // Add to local list
  _savedReadings.add(reading);
  _collectedPoints.add(LatLng(reading.latitude, reading.longitude));
  
  setState(() {
    _pointCount = _savedReadings.length;
  });

  _updateCoverageStats();

  // Show confirmation
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Data collected! GPS Accuracy: ${_currentPosition!.accuracy.toStringAsFixed(1)}m, Altitude: ${_currentPosition!.altitude.toStringAsFixed(1)}m'),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 2),
    ),
  );

  // Auto-navigate to next target if enabled
  if (_autoNavigate && _gridCells.isNotEmpty) {
    _findNextTargetCell();
  }
}
  // ==================== GRID MANAGEMENT ====================

  void _updateCurrentCell() {
    if (_currentPosition == null || _gridCells.isEmpty) return;

    LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    
    for (var cell in _gridCells) {
      if (_isPointInCell(currentLocation, cell)) {
        if (_currentCell != cell) {
          setState(() {
            _currentCell = cell;
            if (cell.status == GridCellStatus.notStarted) {
              cell.status = GridCellStatus.inProgress;
              cell.startTime = DateTime.now();
            }
          });
        }
        break;
      }
    }
  }

  void _findNextTargetCell() {
    if (_gridCells.isEmpty) return;

    GridCell? nextCell;
    
    // Find first uncompleted cell
    for (var cell in _gridCells) {
      if (cell.status == GridCellStatus.notStarted) {
        nextCell = cell;
        break;
      }
    }

    // If no new cells, find in-progress cells
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

    // FIX: Improved navigation with proper timing and error handling
    if (nextCell != null && _autoNavigate && _isMapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          LatLng targetLocation = LatLng(nextCell!.centerLat, nextCell.centerLon);
          double currentZoom = _mapController.camera.zoom;
          
          // Ensure we don't zoom out too far
          double navigationZoom = math.max(currentZoom, 15.0);
          
          _mapController.move(targetLocation, navigationZoom);
          
          // Show navigation feedback
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Navigating to next grid cell'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.blue,
            ),
          );
          
        } catch (e) {
          print('Error navigating to target cell: $e');
        }
      });
    }
  }

  bool _isPointInCell(LatLng point, GridCell cell) {
    if (cell.bounds.length < 3) return false;
    
    // Simple point-in-polygon test using ray casting algorithm
    int intersections = 0;
    for (int i = 0; i < cell.bounds.length; i++) {
      LatLng p1 = cell.bounds[i];
      LatLng p2 = cell.bounds[(i + 1) % cell.bounds.length];
      
      if (((p1.latitude > point.latitude) != (p2.latitude > point.latitude)) &&
          (point.longitude < (p2.longitude - p1.longitude) * 
           (point.latitude - p1.latitude) / (p2.latitude - p1.latitude) + p1.longitude)) {
        intersections++;
      }
    }
    
    return intersections % 2 == 1;
  }

  // ==================== DATA COLLECTION ====================

  void _collectDataPoint() {
    if (_currentPosition == null) {
      _showGpsWarning();
      return;
    }

    LatLng collectPoint = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    
    setState(() {
      _collectedPoints.add(collectPoint);
    });
    
    // Create magnetic reading with PROPER GPS data
    MagneticReading reading = MagneticReading(
      projectId: widget.project?.id ?? 1,
      latitude: collectPoint.latitude,
      longitude: collectPoint.longitude,
      altitude: _currentPosition!.altitude, // FIX: Use actual GPS altitude
      magneticX: _magneticX,
      magneticY: _magneticY,
      magneticZ: _magneticZ,
      totalField: _totalField,
      timestamp: DateTime.now(),
      accuracy: _currentPosition!.accuracy, // FIX: Use actual GPS accuracy
      heading: _heading, // FIX: Use actual compass heading
      notes: 'Manual collection',
    );
    
    // Save to database if not web mode
    if (!_isWebMode && widget.project != null) {
      DatabaseService.instance.insertMagneticReading(reading);
    }
    
    _savedReadings.add(reading);
    _updateCoverageStats();
    
    // Update current cell status
    if (_currentCell != null) {
      _currentCell!.pointCount++;
      if (_currentCell!.pointCount >= 5) {
        _currentCell!.status = GridCellStatus.completed;
        _currentCell!.completedTime = DateTime.now();
        _findNextTargetCell();
      }
    }
    
    // Show feedback with GPS info
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Data collected! Field: ${_totalField.toStringAsFixed(1)}nT | GPS: ±${_currentPosition!.accuracy.toStringAsFixed(1)}m | Alt: ${_currentPosition!.altitude.toStringAsFixed(1)}m'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _updateCoverageStats() {
    if (_gridCells.isNotEmpty) {
      _completedCells = _gridCells.where((cell) => cell.status == GridCellStatus.completed).length;
      _coveragePercentage = (_completedCells / _gridCells.length) * 100;
    } else {
      _completedCells = 0;
      _coveragePercentage = 0.0;
    }
    
    // Fix: Use Set to avoid double counting points
    Set<String> uniquePoints = {};
    
    // Add collected points (current session)
    for (var point in _collectedPoints) {
      uniquePoints.add('${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}');
    }
    
    // Add saved readings (from database)
    for (var reading in _savedReadings) {
      uniquePoints.add('${reading.latitude.toStringAsFixed(6)},${reading.longitude.toStringAsFixed(6)}');
    }
    
    _pointCount = uniquePoints.length;
  }

  // FIX: Intelligent method to determine initial map center
  LatLng _getInitialMapCenter() {
    // Priority 1: Use grid center (where the survey was created)
    if (widget.gridCenter != null) {
      return widget.gridCenter!;
    }
    
    // Priority 2: Use current GPS position if available and reliable
    if (_currentPosition != null && _currentPosition!.accuracy < 100) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    
    // Priority 3: Try to detect approximate region from system timezone
    try {
      final timeZone = DateTime.now().timeZoneOffset;
      final offsetHours = timeZone.inHours;
      
      // Rough timezone to longitude mapping (very approximate)
      double approximateLongitude = offsetHours * 15.0; // 15 degrees per hour
      
      // Use equator as latitude fallback with timezone-based longitude
      return LatLng(0.0, approximateLongitude.clamp(-180.0, 180.0));
    } catch (e) {
      print('Timezone detection failed: $e');
    }
    
    // Priority 4: Ultimate fallback - center of the world
    return LatLng(0.0, 0.0);
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

  void _showGpsWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GPS not calibrated. Move to open sky for better signal.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }


  //==========Floating action button actions=================

  Widget _buildFloatingActionButtons() {
  return Column(
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
      
      SizedBox(height: 12),
      
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
    ],
  );
}

  // ==================== ORIGINAL UI COMPONENTS ====================

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
            icon: Icon(Icons.download),
            onPressed: _exportSurveyData,
            tooltip: 'Export Survey Data',
          ),
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
      floatingActionButton: _buildFloatingActionButtons(),
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
              : widget.gridCenter ?? LatLng(51.5074, -0.1278),
          initialZoom: _currentPosition != null ? 18.0 : 16.0,
          onTap: _onMapTap,
          onMapReady: () {
            setState(() => _isMapReady = true);
            if (_currentPosition != null) {
              Future.delayed(Duration(milliseconds: 100), () {
                if (mounted) {
                  _centerOnCurrentLocation();
                }
              });
            }
          },
        ),
        children: [
          // Base Map Layer
          _buildBaseMapLayer(),
          
          // FIX: Grid Cells Layer with improved rendering
          if (_showGrid && _gridCells.isNotEmpty && _isMapReady)
            PolygonLayer(
              polygons: _gridCells.map((cell) {
                Color cellColor = _getCellColor(cell.status);
                return Polygon(
                  points: cell.bounds,
                  color: cellColor.withOpacity(0.3),
                  borderColor: cellColor,
                  borderStrokeWidth: 2.0,
                );
              }).toList(),
            ),
          
          // Target Cell Highlight
          if (_nextTargetCell != null && _isMapReady)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: _nextTargetCell!.bounds,
                  color: Colors.yellow.withOpacity(0.5),
                  borderColor: Colors.yellow,
                  borderStrokeWidth: 3.0,
                ),
              ],
            ),
          
          // Collected Points
          if (_collectedPoints.isNotEmpty)
            CircleLayer(
              circles: _collectedPoints.map((point) => CircleMarker(
                point: point,
                radius: 4,
                color: Colors.blue,
                borderColor: Colors.white,
                borderStrokeWidth: 1,
              )).toList(),
            ),
          
          // Saved Readings Points  
          if (_savedReadings.isNotEmpty)
            CircleLayer(
              circles: _savedReadings.map((reading) => CircleMarker(
                point: LatLng(reading.latitude, reading.longitude),
                radius: 3,
                color: Colors.green,
                borderColor: Colors.white,
                borderStrokeWidth: 1,
              )).toList(),
            ),
          
          // Team Members
          if (_showTeamMembers && _teamMembers.isNotEmpty)
            CircleLayer(
              circles: _teamMembers
                  .where((member) => member.currentPosition != null)
                  .map((member) => CircleMarker(
                    point: member.currentPosition!,
                    radius: 6,
                    color: member.isOnline ? Colors.green : Colors.grey,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2,
                  )).toList(),
            ),
          
          // FIX: Current Position with enhanced visibility
          if (_currentPosition != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  width: 40,
                  height: 40,
                  child: Transform.rotate(
                    angle: (_heading ?? 0) * math.pi / 180,
                    child: Container(
                      child: CustomPaint(
                        painter: NavigationArrowPainter(
                          heading: _heading ?? 0,
                          isCalibrated: _isGpsCalibrated,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      
      // FIX: Add debug info overlay (only in debug mode)
      if (kDebugMode)
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('DEBUG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                Text('Map Ready: $_isMapReady', style: TextStyle(color: Colors.white, fontSize: 9)),
                Text('Grid Cells: ${_gridCells.length}', style: TextStyle(color: Colors.white, fontSize: 9)),
                if (widget.gridCenter != null)
                  Text('Grid Center: ${widget.gridCenter!.latitude.toStringAsFixed(4)}, ${widget.gridCenter!.longitude.toStringAsFixed(4)}', 
                       style: TextStyle(color: Colors.white, fontSize: 9)),
                if (_currentPosition != null)
                  Text('Current Pos: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}', 
                       style: TextStyle(color: Colors.white, fontSize: 9)),
                Text('Show Grid: $_showGrid', style: TextStyle(color: Colors.white, fontSize: 9)),
              ],
            ),
          ),
        ),
    ],
  );
}

  Widget _buildBaseMapLayer() {
    switch (_currentBaseLayer) {
      case MapBaseLayer.satellite:
        return TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.example.magnetic_survey_app',
        );
      case MapBaseLayer.emag2Magnetic:
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.magnetic_survey_app',
        );
      case MapBaseLayer.openStreetMap:
      default:
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.magnetic_survey_app',
        );
    }
  }

  Widget _buildControlPanel() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        children: [
          // Status Row
          Row(
            children: [
              _buildGpsStatusWidget(),
              SizedBox(width: 8),
              _buildMagneticStatusWidget(),
              Spacer(),
              _buildCompassWidget(),
            ],
          ),
          
          SizedBox(height: 12),
          
          // Controls Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Grid Toggle
              Column(
                children: [
                  IconButton(
                    icon: Icon(_showGrid ? Icons.grid_on : Icons.grid_off),
                    onPressed: () => setState(() => _showGrid = !_showGrid),
                    color: _showGrid ? Colors.blue : Colors.grey,
                  ),
                  Text('Grid', style: TextStyle(fontSize: 10)),
                ],
              ),
              
              // Team Toggle
              Column(
                children: [
                  IconButton(
                    icon: Icon(_showTeamMembers ? Icons.group : Icons.group_outlined),
                    onPressed: () => setState(() => _showTeamMembers = !_showTeamMembers),
                    color: _showTeamMembers ? Colors.green : Colors.grey,
                  ),
                  Text('Team', style: TextStyle(fontSize: 10)),
                ],
              ),
              
              // Auto Navigate Toggle
              Column(
                children: [
                  IconButton(
                    icon: Icon(_autoNavigate ? Icons.navigation : Icons.navigation_outlined),
                    onPressed: () => setState(() => _autoNavigate = !_autoNavigate),
                    color: _autoNavigate ? Colors.orange : Colors.grey,
                  ),
                  Text('Auto', style: TextStyle(fontSize: 10)),
                ],
              ),
              
              // Data Collection
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _isGpsCalibrated ? _collectDataPoint : null,
                    child: Icon(Icons.add_location_alt, size: 20),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: CircleBorder(),
                      padding: EdgeInsets.all(12),
                    ),
                  ),
                  Text('Collect', style: TextStyle(fontSize: 10)),
                ],
              ),
              
              // Center on Location
              Column(
                children: [
                  IconButton(
                    icon: Icon(Icons.my_location),
                    onPressed: _centerOnCurrentLocation,
                    color: Colors.blue,
                  ),
                  Text('Center', style: TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGpsStatusWidget() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isGpsCalibrated ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isGpsCalibrated ? Icons.gps_fixed : Icons.gps_not_fixed,
            size: 14,
            color: _isGpsCalibrated ? Colors.green : Colors.red,
          ),
          SizedBox(width: 4),
          Text(
            'GPS: ±${_gpsAccuracy.toStringAsFixed(1)}m',
            style: TextStyle(fontSize: 11, color: _isGpsCalibrated ? Colors.green[800] : Colors.red[800]),
          ),
        ],
      ),
    );
  }

  Widget _buildMagneticStatusWidget() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isMagneticCalibrated ? Colors.blue.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isMagneticCalibrated ? Icons.compass_calibration : Icons.warning,
            size: 14,
            color: _isMagneticCalibrated ? Colors.blue : Colors.orange,
          ),
          SizedBox(width: 4),
          Text(
            'MAG: ${_totalField.toStringAsFixed(1)}nT',
            style: TextStyle(fontSize: 11, color: _isMagneticCalibrated ? Colors.blue[800] : Colors.orange[800]),
          ),
        ],
      ),
    );
  }

  Widget _buildCompassWidget() {
    if (!_showCompass || _heading == null) return SizedBox.shrink();
    
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: CustomPaint(
        painter: CompassPainter(_heading!),
      ),
    );
  }

  Widget _buildBottomStatsBar() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem('Points', _pointCount.toString(), Icons.location_on),
          _buildStatItem('Coverage', '${_coveragePercentage.toStringAsFixed(1)}%', Icons.pie_chart),
          _buildStatItem('Completed', _completedCells.toString(), Icons.check_circle),
          _buildStatItem('Remaining', (_gridCells.length - _completedCells).toString(), Icons.pending),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.blue[700]),
        SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // ==================== EVENT HANDLERS ====================

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    // Handle map tap for manual point collection if needed
    if (_surveyMode == 'tap') {
      _collectDataPointAt(point);
    }
  }

  void _collectDataPointAt(LatLng point) {
    setState(() {
      _collectedPoints.add(point);
    });
    
    MagneticReading reading = MagneticReading(
      projectId: widget.project?.id ?? 1,
      latitude: point.latitude,
      longitude: point.longitude,
      altitude: _currentPosition?.altitude ?? 0.0, // Use current GPS altitude if available
      magneticX: _magneticX,
      magneticY: _magneticY,
      magneticZ: _magneticZ,
      totalField: _totalField,
      timestamp: DateTime.now(),
      accuracy: _currentPosition?.accuracy ?? 0.0, // Use current GPS accuracy
      heading: _heading, // Current compass heading
      notes: 'Manual tap collection',
    );
    
    if (!_isWebMode && widget.project != null) {
      DatabaseService.instance.insertMagneticReading(reading);
    }
    
    _savedReadings.add(reading);
    _updateCoverageStats();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Data point collected at tapped location - GPS accuracy: ${_currentPosition?.accuracy?.toStringAsFixed(1) ?? "N/A"}m'),
        duration: Duration(seconds: 1),
        backgroundColor: Colors.blue,
      ),
    );
  }



 // ==================== Automatic Data collection ====================






  void _toggleAutomaticCollection() {
    setState(() {
      _isCollecting = !_isCollecting;
    });

    if (_isCollecting) {
      _startAutomaticCollection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Automatic data collection started'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      _stopAutomaticCollection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Automatic data collection stopped'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _startAutomaticCollection() {
    _automaticCollectionTimer = Timer.periodic(_magneticPullRate, (timer) {
      if (!_isCollecting || !mounted) {
        timer.cancel();
        return;
      }
      _recordMagneticReading(); // Use the new method
    });
  }

  void _stopAutomaticCollection() {
    _automaticCollectionTimer?.cancel();
    _automaticCollectionTimer = null;
  }



//===================== MAP INTERACTIONS ====================
  void _centerOnCurrentLocation() {
    if (_currentPosition != null && _isMapReady) {
      try {
        LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        _mapController.move(currentLocation, 16.0);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Centered on current location'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.blue,
          ),
        );
      } catch (e) {
        print('Error centering on current location: $e');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location not available'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ==================== EXPORT FUNCTIONALITY ====================

void _exportSurveyData() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.download, color: Colors.blue),
          SizedBox(width: 8),
          Text('Export Survey Data'),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Choose export format for your survey data:'),
            SizedBox(height: 16),
            ...ExportFormat.values.map((format) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(_getFormatIcon(format), color: _getFormatColor(format)),
                title: Text(_getFormatName(format)),
                onTap: () => _performExport(format),
              ),
            )).toList(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
      ],
    ),
  );
}

  Widget _buildExportFormatButton(ExportFormat format, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          _performExport(format);
        },
        icon: Icon(icon),
        label: Text(_getFormatDisplayName(format)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
    );
  }

  String _getFormatDisplayName(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        return 'CSV Spreadsheet';
      case ExportFormat.geojson:
        return 'GeoJSON';
      case ExportFormat.kml:
        return 'Google Earth KML';
      case ExportFormat.sqlite:
        return 'SQLite Database';
      case ExportFormat.shapefile:
        return 'Shapefile (WKT)';
    }
  }

Future<void> _performExport(ExportFormat format) async {
  final navigator = Navigator.of(context);
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  
  navigator.pop();
  
  try {
    // Show loading
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(width: 16),
            Text('Exporting ${_savedReadings.length} data points...'),
          ],
        ),
        duration: Duration(seconds: 3),
      ),
    );

    // Create project for export
    final project = widget.project ?? SurveyProject(
      id: DateTime.now().millisecondsSinceEpoch,
      name: 'Survey Export',
      description: 'Exported survey data',
      createdAt: DateTime.now(),
    );

    // Export data
    String exportData = await ExportService.instance.exportProject(
      project: project,
      readings: _savedReadings,
      gridCells: _gridCells,
      fieldNotes: [],
      format: format,
    );

    // Generate filename
    String extension = _getFileExtension(format);
    String filename = '${project.name}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    
    // Save and share
    await ExportService.instance.saveAndShare(
      data: exportData,
      filename: filename,
      mimeType: _getMimeType(format),
    );

    scaffoldMessenger.hideCurrentSnackBar();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('${_savedReadings.length} data points exported successfully!'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'Share Again',
          onPressed: () => _performExport(format),
        ),
      ),
    );
  } catch (e) {
    scaffoldMessenger.hideCurrentSnackBar();
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  // ==================== SETTINGS AND DIALOGS ====================

  void _showSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Survey Settings'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: Text('Show Grid'),
                    value: _showGrid,
                    onChanged: (value) {
                      setDialogState(() => _showGrid = value);
                      setState(() => _showGrid = value);
                    },
                  ),
                  SwitchListTile(
                    title: Text('Show Team Members'),
                    value: _showTeamMembers,
                    onChanged: (value) {
                      setDialogState(() => _showTeamMembers = value);
                      setState(() => _showTeamMembers = value);
                    },
                  ),
                  SwitchListTile(
                    title: Text('Auto Navigate'),
                    value: _autoNavigate,
                    onChanged: (value) {
                      setDialogState(() => _autoNavigate = value);
                      setState(() => _autoNavigate = value);
                    },
                  ),
                  SwitchListTile(
                    title: Text('Show Compass'),
                    value: _showCompass,
                    onChanged: (value) {
                      setDialogState(() => _showCompass = value);
                      setState(() => _showCompass = value);
                    },
                  ),
                  ListTile(
                    title: Text('Survey Mode'),
                    subtitle: DropdownButton<String>(
                      value: _surveyMode,
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setDialogState(() => _surveyMode = newValue);
                          setState(() => _surveyMode = newValue);
                        }
                      },
                      items: <String>['manual', 'automatic', 'tap']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value.toUpperCase()),
                        );
                      }).toList(),
                    ),
                  ),
                  ListTile(
                    title: Text('Base Map Layer'),
                    subtitle: DropdownButton<MapBaseLayer>(
                      value: _currentBaseLayer,
                      onChanged: (MapBaseLayer? newValue) {
                        if (newValue != null) {
                          setDialogState(() => _currentBaseLayer = newValue);
                          setState(() => _currentBaseLayer = newValue);
                        }
                      },
                      items: MapBaseLayer.values.map<DropdownMenuItem<MapBaseLayer>>((MapBaseLayer value) {
                        return DropdownMenuItem<MapBaseLayer>(
                          value: value,
                          child: Text(value.toString().split('.').last),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Survey Help'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Grid Survey Instructions:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('• Green grid cells are completed'),
                Text('• Orange cells are in progress'),
                Text('• Grey cells are not started'),
                Text('• Yellow highlight shows next target cell'),
                SizedBox(height: 12),
                Text('Controls:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('• Tap "Collect" to record data at current location'),
                Text('• Use "Center" to center map on your location'),
                Text('• Toggle grid/team visibility with control buttons'),
                Text('• Enable auto-navigation to move to next cells automatically'),
                SizedBox(height: 12),
                Text('Status Indicators:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('• GPS accuracy should be <10m (green)'),
                Text('• Magnetic calibration auto-activates when moving'),
                Text('• Blue dot shows your current position'),
                Text('• Compass shows your heading direction'),
                SizedBox(height: 12),
                Text('Worldwide Usage:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('• App works anywhere in the world'),
                Text('• Grid appears at its creation location'),
                Text('• GPS automatically adapts to local coordinates'),
                Text('• Map centers on grid or your current location'),
                SizedBox(height: 12),
                Text('Navigation:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('• Your blue position dot shows where you are relative to the grid'),
                Text('• Navigate to grid cells to start data collection'),
                Text('• Use "Center" button if you get lost'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Got it'),
            ),
          ],
        );
      },
    );
  }


  // Helper methods - add these at the end of the class
String _getFileExtension(ExportFormat format) {
  switch (format) {
    case ExportFormat.csv: return 'csv';
    case ExportFormat.geojson: return 'geojson';
    case ExportFormat.kml: return 'kml';
    case ExportFormat.sqlite: return 'db';
    case ExportFormat.shapefile: return 'shp';
  }
}

String _getMimeType(ExportFormat format) {
  switch (format) {
    case ExportFormat.csv: return 'text/csv';
    case ExportFormat.geojson: return 'application/geo+json';
    case ExportFormat.kml: return 'application/vnd.google-earth.kml+xml';
    case ExportFormat.sqlite: return 'application/x-sqlite3';
    case ExportFormat.shapefile: return 'application/x-shapefile';
  }
}

String _getFormatName(ExportFormat format) {
  switch (format) {
    case ExportFormat.csv: return 'CSV Spreadsheet';
    case ExportFormat.geojson: return 'GeoJSON';
    case ExportFormat.kml: return 'Google Earth KML';
    case ExportFormat.sqlite: return 'SQLite Database';
    case ExportFormat.shapefile: return 'Shapefile';
  }
}

IconData _getFormatIcon(ExportFormat format) {
  switch (format) {
    case ExportFormat.csv: return Icons.table_chart;
    case ExportFormat.geojson: return Icons.map;
    case ExportFormat.kml: return Icons.public;
    case ExportFormat.sqlite: return Icons.storage;
    case ExportFormat.shapefile: return Icons.layers;
  }
}

Color _getFormatColor(ExportFormat format) {
  switch (format) {
    case ExportFormat.csv: return Colors.green;
    case ExportFormat.geojson: return Colors.blue;
    case ExportFormat.kml: return Colors.orange;
    case ExportFormat.sqlite: return Colors.purple;
    case ExportFormat.shapefile: return Colors.teal;
  }
}
}

// ==================== CUSTOM PAINTERS ====================

class CompassPainter extends CustomPainter {
  final double heading;

  CompassPainter(this.heading);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Draw compass background
    Paint backgroundPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, backgroundPaint);
    
    // Draw N marker
    TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 8),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - radius + 3));
    
    // Draw heading needle
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((heading * math.pi) / 180);
    
    Paint needlePaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    ui.Path needlePath = ui.Path();
    needlePath.moveTo(0, -radius + 8);
    needlePath.lineTo(-2, 0);
    needlePath.lineTo(2, 0);
    needlePath.close();
    
    canvas.drawPath(needlePath, needlePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CompassPainter oldDelegate) {
    return oldDelegate.heading != heading;
  }
}



class NavigationArrowPainter extends CustomPainter {
  final double heading;
  final bool isCalibrated;

  NavigationArrowPainter({
    required this.heading, 
    required this.isCalibrated
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Outer circle (accuracy indicator)
    final outerPaint = Paint()
      ..color = isCalibrated ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, outerPaint);

    // Border circle
    final borderPaint = Paint()
      ..color = isCalibrated ? Colors.green : Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 1, borderPaint);

    // Inner circle (base)
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 4, innerPaint);

    // Navigation arrow pointing up (rotation handled by Transform.rotate)
    final arrowPaint = Paint()
      ..color = isCalibrated ? Colors.green : Colors.orange
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(center.dx, center.dy - (radius - 8));
    path.lineTo(center.dx - 6, center.dy - (radius - 16));
    path.lineTo(center.dx - 3, center.dy - (radius - 16));
    path.lineTo(center.dx - 3, center.dy + (radius - 16));
    path.lineTo(center.dx + 3, center.dy + (radius - 16));
    path.lineTo(center.dx + 3, center.dy - (radius - 16));
    path.lineTo(center.dx + 6, center.dy - (radius - 16));
    path.close();
    canvas.drawPath(path, arrowPaint);

    // Center dot
    final centerDotPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3, centerDotPaint);
  }

  @override
  bool shouldRepaint(NavigationArrowPainter oldDelegate) {
    return oldDelegate.heading != heading || oldDelegate.isCalibrated != isCalibrated;
  }
}