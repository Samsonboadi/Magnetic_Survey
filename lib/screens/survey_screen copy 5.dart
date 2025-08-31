// Enhanced Production Survey Screen with Bug Fixes
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
//import '../widgets/emag2_layer.dart'; // Import the new EMAG2 layer

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
  // Controllers and core state
  final MapController _mapController = MapController();
  Position? _currentPosition;
  double? _heading;
  final bool _isWebMode = kIsWeb;


  bool _isMapOrientationEnabled = false;
  double? _lastHeading;
  Timer? _orientationUpdateTimer;

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
  bool _showTeamMembers = false;
  bool _showCompass = true;
  bool _autoNavigate = true;
  bool _isCollecting = false;
  bool _isTeamMode = false;
  bool _hasLocationError = false;
  bool _needsTargetCellUpdate = false;
  bool _isMapReady = false;
  bool _isTaskBarCollapsed = false;
  bool _followLocation = true; // FIXED: Default to true
  String _surveyMode = 'manual';
  MapBaseLayer _currentBaseLayer = MapBaseLayer.openStreetMap;

  // Data collection state tracking
  bool _showDataBanner = false;
  Timer? _bannerHideTimer;

  // FIXED: Magnetic field color scale constants (microTesla range for smartphones)
  static const double MIN_MAGNETIC_FIELD = 20.0;  // Changed from 53814.0
  static const double MAX_MAGNETIC_FIELD = 70.0;  // Changed from 56767.0



  MagneticReading? _selectedReading;
  bool _showPopup = false;
  Offset _popupPosition = Offset.zero;


  // Timers and controllers
  Duration _magneticPullRate = Duration(seconds: 1);
  Timer? _automaticCollectionTimer;
  Timer? _webSimulationTimer;
  Timer? _bannerTimer;
  late AnimationController _taskBarAnimationController;
  late Animation<double> _taskBarAnimation;

  // Stream subscriptions
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<TeamMember>>? _teamSubscription;

  // Services
  TeamSyncService? _teamService;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _taskBarAnimationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _taskBarAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _taskBarAnimationController,
      curve: Curves.easeInOut,
    ));

    // Initialize grid if provided
    if (widget.initialGridCells != null) {
      setState(() {
        _gridCells = widget.initialGridCells!;
      });
    }

    // Start core services
    _initializeLocation();
    _startSensorListening();
    _loadPreviousSurveyData();

    // Web simulation for testing
    if (_isWebMode) {
      _simulateDataForWeb();
    }
  }

  @override
  void dispose() {
    _taskBarAnimationController.dispose();
    _automaticCollectionTimer?.cancel();
    _webSimulationTimer?.cancel();
    _bannerTimer?.cancel();
    _bannerHideTimer?.cancel();
    _magnetometerSubscription?.cancel();
    _compassSubscription?.cancel();
    _positionSubscription?.cancel();
    _teamSubscription?.cancel();
    _teamService?.dispose();
    _orientationUpdateTimer?.cancel();
    super.dispose();
  }




 // ==================Map Orientation====================

 void _toggleMapOrientation() {
  setState(() {
    _isMapOrientationEnabled = !_isMapOrientationEnabled;
  });

  if (_isMapOrientationEnabled) {
    // Start orientation updates
    _startMapOrientationUpdates();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Map orientation enabled - Map will rotate to your heading'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  } else {
    // Stop orientation updates and reset to north
    _stopMapOrientationUpdates();
    _resetMapToNorth();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Map orientation disabled - Map reset to north'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

void _startMapOrientationUpdates() {
  _orientationUpdateTimer?.cancel();
  _orientationUpdateTimer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
    if (_heading != null && _isMapOrientationEnabled && _isMapReady) {
      // Only update if heading has changed significantly (more than 10 degrees)
      // This prevents jittery rotation from small compass variations
      if (_lastHeading == null || (_heading! - _lastHeading!).abs() > 10.0) {
        _updateMapRotation(_heading!);
        _lastHeading = _heading;
      }
    }
  });
}

void _stopMapOrientationUpdates() {
  _orientationUpdateTimer?.cancel();
  _orientationUpdateTimer = null;
  _lastHeading = null;
}

void _updateMapRotation(double heading) {
  try {
    // Convert heading to radians for the map rotation
    // Negate the heading because flutter_map rotates clockwise (from north)
    double rotationRadians = -heading * (math.pi / 180.0);
    
    // Get current camera position
    final currentCamera = _mapController.camera;
    
    // Use moveAndRotate for smooth rotation transition
    _mapController.moveAndRotate(
      currentCamera.center, // Keep same center position
      currentCamera.zoom,   // Keep same zoom level
      rotationRadians,      // Apply new rotation
    );
    
    if (kDebugMode) {
      print('Map rotated to heading: ${heading.toStringAsFixed(1)}°');
    }
  } catch (e) {
    print('Error updating map rotation: $e');
    // Fallback: try simple rotation
    try {
      double rotationRadians = -heading * (math.pi / 180.0);
      _mapController.rotate(rotationRadians);
    } catch (fallbackError) {
      print('Fallback rotation also failed: $fallbackError');
    }
  }
}

void _resetMapToNorth() {
  try {
    if (_isMapReady) {
      final currentCamera = _mapController.camera;
      _mapController.moveAndRotate(
        currentCamera.center,
        currentCamera.zoom,
        0.0, // Reset rotation to 0 (north up)
      );
    }
  } catch (e) {
    print('Error resetting map to north: $e');
  }
}






  // ==================== INITIALIZATION METHODS ====================

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
          
          // FIXED: Wait for map to be ready before centering
          _waitForMapReadyThenCenter();
        }
        
        // Set up position stream
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
            
            // FIXED: Only auto-follow if enabled AND map is ready
            if (_followLocation && _isMapReady) {
              try {
                LatLng currentLocation = LatLng(position.latitude, position.longitude);
                _mapController.move(currentLocation, _mapController.camera.zoom);
              } catch (e) {
                print('Map controller not ready for auto-navigation: $e');
              }
            }
            
            // Team position update
            if (_isTeamMode && _teamService != null) {
              _teamService!.updateMyPosition(
                LatLng(position.latitude, position.longitude), 
                _heading
              );
            }
          }
        });
      }
    } catch (e) {
      print('Location error: $e');
      setState(() {
        _hasLocationError = true;
      });
    }
  }

  // FIXED: Helper method to wait for map ready then center
  void _waitForMapReadyThenCenter() {
    Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (_isMapReady && _currentPosition != null) {
        timer.cancel();
        try {
          LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
          _mapController.move(currentLocation, 16.0);
          print('Initial location centered: $currentLocation');
        } catch (e) {
          print('Error centering on initial location: $e');
        }
      } else if (timer.tick > 50) { // 5 second timeout
        timer.cancel();
        print('Timeout waiting for map to be ready');
      }
    });
  }

  void _startSensorListening() {
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      if (mounted) {
        setState(() {
          _magneticX = event.x - _magneticCalibrationX;
          _magneticY = event.y - _magneticCalibrationY;
          _magneticZ = event.z - _magneticCalibrationZ;
          _totalField = math.sqrt(_magneticX * _magneticX + _magneticY * _magneticY + _magneticZ * _magneticZ);
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
        _totalField = math.sqrt(_magneticX * _magneticX + _magneticY * _magneticY + _magneticZ * _magneticZ);
        _heading = (math.Random().nextDouble() * 360);
        _gpsAccuracy = 2.0 + math.Random().nextDouble() * 3;
      });
    });
  }

  Future<void> _loadPreviousSurveyData() async {
    if (_isWebMode || widget.project == null) return;
    
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

  // ==================== MAGNETIC FIELD COLOR MAPPING ====================
  
  Color getMagneticFieldColor(double totalField) {
    // DEBUG: Print values to verify the fix works
    if (kDebugMode) {
      print('Total Field: $totalField μT, Range: $MIN_MAGNETIC_FIELD-$MAX_MAGNETIC_FIELD μT');
    }
    
    // Normalize the value between 0 and 1
    double normalized = (totalField - MIN_MAGNETIC_FIELD) / (MAX_MAGNETIC_FIELD - MIN_MAGNETIC_FIELD);
    normalized = math.max(0.0, math.min(1.0, normalized)); // Clamp between 0 and 1
    
    // DEBUG: Print normalized value
    if (kDebugMode) {
      print('Normalized value: $normalized');
    }
    
    // Create spectral color mapping (blue -> cyan -> green -> yellow -> red)
    if (normalized < 0.25) {
      double t = normalized / 0.25;
      return Color.lerp(Colors.blue[900]!, Colors.cyan, t)!;
    } else if (normalized < 0.5) {
      double t = (normalized - 0.25) / 0.25;
      return Color.lerp(Colors.cyan, Colors.green, t)!;
    } else if (normalized < 0.75) {
      double t = (normalized - 0.5) / 0.25;
      return Color.lerp(Colors.green, Colors.yellow, t)!;
    } else {
      double t = (normalized - 0.75) / 0.25;
      return Color.lerp(Colors.yellow, Colors.red[900]!, t)!;
    }
  }

  // ==================== MAP CONFIGURATION ====================

  Widget _buildBaseMapLayer() {
    switch (_currentBaseLayer) {
      case MapBaseLayer.satellite:
        return TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.example.magnetic_survey_app',
        );
      case MapBaseLayer.emag2Magnetic:
        // FIXED: Use simple OpenStreetMap base with EMAG2 overlay
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

  LatLng _getInitialMapCenter() {
    if (_currentPosition != null && _currentPosition!.accuracy < 100) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    
    if (widget.gridCenter != null) {
      return widget.gridCenter!;
    }
    
    // Fallback to equator
    return LatLng(0.0, 0.0);
  }

  // ==================== DATA COLLECTION ====================

Future<void> _recordMagneticReading() async {
  if (_currentPosition == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GPS position not available. Please wait for location fix.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  if (!_isGpsCalibrated) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GPS accuracy is poor. Consider waiting for better signal.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  final reading = MagneticReading(
    latitude: _currentPosition!.latitude,
    longitude: _currentPosition!.longitude,
    altitude: _currentPosition!.altitude ?? 0.0,
    magneticX: _magneticX,
    magneticY: _magneticY,
    magneticZ: _magneticZ,
    totalField: _totalField,
    timestamp: DateTime.now(),
    projectId: widget.project?.id ?? 1,
    accuracy: _gpsAccuracy,
    heading: _heading,
  );

  try {
    if (!_isWebMode) {
      await DatabaseService.instance.insertMagneticReading(reading);
      _savedReadings.add(reading);
    }
    
    setState(() {
      _collectedPoints.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
      _pointCount = _savedReadings.length + _collectedPoints.length;
    });

    // IMPROVED: Update grid cell status based on actual points inside cells
    _updateGridCellStatus();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Point recorded! Total: $_pointCount readings'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error saving reading: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}


void _updateGridCellStatus() {
  if (_gridCells.isEmpty || _currentPosition == null) return;

  LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
  
  // Check each grid cell and count points actually inside it
  for (int i = 0; i < _gridCells.length; i++) {
    final cell = _gridCells[i];
    
    // Count ALL points (both collected and saved) that are inside this cell
    int pointsInCell = 0;
    
    // Count collected points in this cell
    for (var point in _collectedPoints) {
      if (_isPointInCell(point, cell)) {
        pointsInCell++;
      }
    }
    
    // Count saved readings in this cell
    for (var reading in _savedReadings) {
      LatLng readingPoint = LatLng(reading.latitude, reading.longitude);
      if (_isPointInCell(readingPoint, cell)) {
        pointsInCell++;
      }
    }
    
    // Update cell status based on actual points inside
    GridCellStatus newStatus = cell.status;
    
    if (pointsInCell >= 2) { // REQUIREMENT: At least 2 points inside
      newStatus = GridCellStatus.completed;
      if (cell.status != GridCellStatus.completed) {
        _gridCells[i].completedTime = DateTime.now();
      }
    } else if (pointsInCell >= 1) {
      newStatus = GridCellStatus.inProgress;
      if (cell.status == GridCellStatus.notStarted) {
        _gridCells[i].startTime = DateTime.now();
      }
    }
    
    // Update the cell
    setState(() {
      _gridCells[i].status = newStatus;
      _gridCells[i].pointCount = pointsInCell;
    });
  }
  
  // Update coverage stats
  _updateCoverageStats();
  
  // Find next target cell
  _findNextTargetCell();
}

// ==================== IMPROVED POINT-IN-POLYGON TEST ====================

bool _isPointInCell(LatLng point, GridCell cell) {
  if (cell.bounds.length < 3) return false;
  
  // Ray casting algorithm for point-in-polygon test
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
void _toggleAutomaticCollection() {
  setState(() {
    _isCollecting = !_isCollecting;
  });

  if (_isCollecting) {
    _automaticCollectionTimer = Timer.periodic(_magneticPullRate, (timer) {
      if (mounted && _isCollecting) {
        _recordMagneticReading();
      } else {
        timer.cancel();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Automatic recording started - Each grid cell needs 2+ points'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  } else {
    _automaticCollectionTimer?.cancel();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Automatic recording stopped'),
        backgroundColor: Colors.orange,
      ),
    );
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

  void _showTemporaryDataBanner() {
    setState(() {
      _showDataBanner = true;
    });
    
    _bannerHideTimer?.cancel();
    _bannerHideTimer = Timer(Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showDataBanner = false;
        });
      }
    });
  }

  // ==================== UI COMPONENTS ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildMinimalAppBar(),
      body: Stack(
        children: [
          _buildFullScreenMapView(),
          
          // Floating status widgets
          Positioned(
            top: 10,
            left: 10,
            child: _buildFloatingStatusWidgets(),
          ),
          
          // FIXED: Location follow toggle button
          Positioned(
            top: 80,
            right: 10,
            child: _buildLocationFollowButton(),
          ),
          
          // Magnetic scale legend
          Positioned(
            top: 10,
            right: 10,
            child: _buildMagneticScale(),
          ),
          
          // Collapsible task bar
          _buildCollapsibleTaskBar(),
          
          // Data collection banner
          if (_showDataBanner)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: _buildDataBanner(),
            ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildFullScreenMapView() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _getInitialMapCenter(),
        initialZoom: _currentPosition != null ? 16.0 : 10.0,
        minZoom: 3.0,
        maxZoom: 22.0,
        onMapReady: () {
          print('Map is now ready');
          setState(() => _isMapReady = true);
          
          // FIXED: Center on current location when map becomes ready
          if (_currentPosition != null) {
            LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
            _mapController.move(currentLocation, 16.0);
            print('Map ready - centered on current location: $currentLocation');
          }
          
          if (widget.gridCenter != null) {
            _navigateToGridCenter();
          }
        },
        onTap: _onMapTap,
      ),
      children: [
        _buildBaseMapLayer(),
        
        // FIXED: EMAG2 Global Overlay (simple approach that works with Flutter Map 8.x)
        if (_currentBaseLayer == MapBaseLayer.emag2Magnetic)
          OverlayImageLayer(
            overlayImages: [
              OverlayImage(
                bounds: LatLngBounds(
                  LatLng(-90, -180), // Global coverage
                  LatLng(90, 180),
                ),
                imageProvider: NetworkImage(
                  'https://gis.ngdc.noaa.gov/arcgis/rest/services/EMAG2v3/ImageServer/exportImage'
                  '?bbox=-180,-90,180,90'
                  '&size=1024,512'
                  '&format=png'
                  '&f=image'
                  '&transparent=true'
                  '&interpolation=RSP_BilinearInterpolation',
                ),
                opacity: 0.6,
              ),
            ],
          ),
        
        // Grid overlay
        if (_showGrid && _gridCells.isNotEmpty)
          PolygonLayer(
            polygons: _gridCells.map((cell) => Polygon(
              points: cell.bounds,
              color: _getCellColor(cell.status).withOpacity(0.3),
              borderStrokeWidth: 1.0,
              borderColor: _getCellColor(cell.status),
            )).toList(),
          ),

        // FIXED: Collected points with corrected magnetic field colors
        MarkerLayer(
          markers: _collectedPoints.asMap().entries.map((entry) {
            int index = entry.key;
            LatLng point = entry.value;
            
            double magneticValue = _totalField;
            if (index < _savedReadings.length) {
              magneticValue = _savedReadings[index].totalField;
            }
            
            Color pointColor = getMagneticFieldColor(magneticValue);
            
            if (kDebugMode && index == _collectedPoints.length - 1) {
              print('Point $index: $magneticValue μT -> Color: $pointColor');
            }
            
            return Marker(
              point: point,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: pointColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // Current position marker
        if (_currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _heading != null
                      ? Transform.rotate(
                          angle: (_heading! > 0 ? _heading! : 0) * math.pi / 180,
                          child: Icon(Icons.navigation, color: Colors.white, size: 12),
                        )
                      : Icon(Icons.person, color: Colors.white, size: 12),
                ),
              ),
            ],
          ),

        // Team members
        if (_isTeamMode && _showTeamMembers)
          MarkerLayer(
            markers: _teamMembers.map((member) => Marker(
              point: member.currentPosition ?? LatLng(0, 0), // FIXED: Use currentPosition, not lastKnownPosition
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: member.markerColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: member.isOnline
                    ? Icon(Icons.person, color: Colors.white, size: 8)
                    : Icon(Icons.person_outline, color: Colors.white, size: 8),
              ),
            )).where((marker) => (marker.point.latitude != 0 || marker.point.longitude != 0)).toList(), // Filter out null positions
          ),
      ],
    );
  }

  // FIXED: Enhanced location follow button with immediate action
  Widget _buildLocationFollowButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _followLocation = !_followLocation;
        });
        
        // FIXED: Immediately center on current location when enabled
        if (_followLocation && _currentPosition != null && _isMapReady) {
          try {
            LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
            _mapController.move(currentLocation, _mapController.camera.zoom);
            print('Follow location enabled - centered on: $currentLocation');
          } catch (e) {
            print('Error centering on location: $e');
          }
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_followLocation 
                ? 'Location following enabled' 
                : 'Location following disabled'),
            backgroundColor: _followLocation ? Colors.green : Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _followLocation ? Colors.blue.withOpacity(0.9) : Colors.grey.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          _followLocation ? Icons.my_location : Icons.location_searching,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildFloatingStatusWidgets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GPS Status
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isGpsCalibrated ? Colors.green.withOpacity(0.9) : Colors.red.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isGpsCalibrated ? Icons.gps_fixed : Icons.gps_not_fixed,
                size: 18,
                color: Colors.white,
              ),
              SizedBox(width: 6),
              Text(
                'GPS: ±${_gpsAccuracy.toStringAsFixed(1)}m',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: 8),
        
        // FIXED: Magnetometer Status with correct units
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isMagneticCalibrated ? Colors.blue.withOpacity(0.9) : Colors.orange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isMagneticCalibrated ? Icons.compass_calibration : Icons.warning,
                size: 18,
                color: Colors.white,
              ),
              SizedBox(width: 6),
              Text(
                'Mag: ${_totalField.toStringAsFixed(1)}μT', // FIXED: Show μT instead of nT
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // FIXED: Magnetic scale with correct units and range
  Widget _buildMagneticScale() {
    return Container(
      width: 200,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // FIXED: Title with correct units
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Magnetic Field (μT)', // Changed from (nT) to (μT)
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          
          // Color scale bar with corrected labels
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [
                    Colors.blue[900]!,
                    Colors.cyan,
                    Colors.green,
                    Colors.yellow,
                    Colors.red[900]!,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      '${MIN_MAGNETIC_FIELD.toInt()}', // Will show "20"
                      style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Text(
                      '${MAX_MAGNETIC_FIELD.toInt()}', // Will show "70"
                      style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleTaskBar() {
    return Positioned(
      bottom: 20,
      left: 20,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isTaskBarCollapsed = !_isTaskBarCollapsed;
          });
          if (_isTaskBarCollapsed) {
            _taskBarAnimationController.forward();
          } else {
            _taskBarAnimationController.reverse();
          }
        },
        child: AnimatedBuilder(
          animation: _taskBarAnimation,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[800],
                      borderRadius: _isTaskBarCollapsed 
                          ? BorderRadius.circular(12)
                          : BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.analytics, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Survey Stats',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          _isTaskBarCollapsed 
                              ? Icons.keyboard_arrow_up 
                              : Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                  
                  if (!_isTaskBarCollapsed)
                    Container(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStatItem('Points', _pointCount.toString(), Icons.location_on),
                              SizedBox(width: 20),
                              _buildStatItem('Coverage', '${_coveragePercentage.toStringAsFixed(1)}%', Icons.grid_on),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStatItem('Field', '${_totalField.toStringAsFixed(1)}μT', Icons.sensors),
                              SizedBox(width: 20),
                              _buildStatItem('Accuracy', '±${_gpsAccuracy.toStringAsFixed(1)}m', Icons.gps_fixed),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
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
            Icon(icon, size: 14, color: Colors.grey[600]),
            SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildDataBanner() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Data collected! GPS: ±${_gpsAccuracy.toStringAsFixed(1)}m, Altitude: ${_currentPosition?.altitude.toStringAsFixed(1) ?? "N/A"}m',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: () {
              setState(() {
                _showDataBanner = false;
              });
              _bannerHideTimer?.cancel();
            },
          ),
        ],
      ),
    );
  }

Widget _buildFloatingActionButtons() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // MAP ORIENTATION BUTTON - NEW (add this as the first button)
      FloatingActionButton.small(
        heroTag: "map_orientation",
        onPressed: _toggleMapOrientation,
        backgroundColor: _isMapOrientationEnabled ? Colors.deepPurple : Colors.grey,
        child: Icon(
          _isMapOrientationEnabled ? Icons.explore : Icons.explore_outlined,
          color: Colors.white,
          size: 20,
        ),
        tooltip: _isMapOrientationEnabled 
            ? 'Disable Map Orientation' 
            : 'Enable Map Orientation',
      ),
      
      SizedBox(height: 12),
      
      // YOUR EXISTING BUTTONS (keep all your existing floating action buttons here)
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
      
      SizedBox(height: 12),
      
      // Compass Toggle Button (keep your existing compass button)
      FloatingActionButton.small(
        heroTag: "compass_toggle",
        onPressed: () => setState(() => _showCompass = !_showCompass),
        backgroundColor: _showCompass ? Colors.purple : Colors.grey,
        child: Icon(
          _showCompass ? Icons.explore_off : Icons.compass_calibration, 
          color: Colors.white,
          size: 20,
        ),
        tooltip: _showCompass ? 'Hide Compass' : 'Show Compass',
      ),
      
      // ADD ANY OTHER EXISTING BUTTONS YOU HAVE HERE...
    ],
  );
}

  PreferredSizeWidget _buildMinimalAppBar() {
    return AppBar(
      title: Text(
        widget.project?.name ?? 'Survey Session',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.blue[800],
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          icon: Icon(Icons.download),
          onPressed: _exportSurveyData,
          tooltip: 'Export Survey Data',
        ),
        IconButton(
          icon: Icon(Icons.settings),
          onPressed: _showSettings,
          tooltip: 'Settings & Teams',
        ),
      ],
    );
  }

  // ==================== HELPER METHODS ====================

void _updateCoverageStats() {
  if (_gridCells.isNotEmpty) {
    _completedCells = _gridCells.where((cell) => cell.status == GridCellStatus.completed).length;
    _coveragePercentage = (_completedCells / _gridCells.length) * 100.0;
  } else {
    _completedCells = 0;
    _coveragePercentage = 0.0;
  }
  
  // Use Set to avoid double counting points
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

  void _navigateToGridCenter() {
    if (widget.gridCenter == null || !_isMapReady) return;
    
    try {
      double zoomLevel = 15.0;
      if (_gridCells.isNotEmpty) {
        zoomLevel = _calculateOptimalZoom();
      }
      
      print('Moving to grid center: ${widget.gridCenter} with zoom: $zoomLevel');
      _mapController.move(widget.gridCenter!, zoomLevel);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grid loaded - ${_gridCells.length} cells ready for survey'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error navigating to grid center: $e');
    }
  }

  double _calculateOptimalZoom() {
    if (_gridCells.isEmpty) return 16.0;
    
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
    
    double latDiff = maxLat - minLat;
    double lngDiff = maxLng - minLng;
    double maxDiff = math.max(latDiff, lngDiff);
    
    if (maxDiff > 0.01) return 13.0;
    if (maxDiff > 0.005) return 14.0;
    if (maxDiff > 0.002) return 15.0;
    return 16.0;
  }

  LatLngBounds? _calculateGridBounds() {
    if (_gridCells.isEmpty) return null;
    
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    
    for (var cell in _gridCells) {
      for (var corner in cell.bounds) {
        minLat = math.min(minLat, corner.latitude);
        maxLat = math.max(maxLat, corner.latitude);
        minLng = math.min(minLng, corner.longitude);
        maxLng = math.max(maxLng, corner.longitude);
      }
    }
    
    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  bool _isPositionInBounds(LatLng position, LatLngBounds bounds) {
    return position.latitude >= bounds.south &&
           position.latitude <= bounds.north &&
           position.longitude >= bounds.west &&
           position.longitude <= bounds.east;
  }

void _findNextTargetCell() {
  if (_gridCells.isEmpty) return;

  GridCell? nextCell;
  
  // Priority 1: Find cells that need more points (have 1 point, need 2)
  for (var cell in _gridCells) {
    if (cell.status == GridCellStatus.inProgress && cell.pointCount < 2) {
      nextCell = cell;
      break;
    }
  }
  
  // Priority 2: Find completely unstarted cells
  if (nextCell == null) {
    for (var cell in _gridCells) {
      if (cell.status == GridCellStatus.notStarted) {
        nextCell = cell;
        break;
      }
    }
  }

  setState(() {
    _nextTargetCell = nextCell;
    _currentCell = nextCell;
  });

  print('Next target cell: ${nextCell?.id ?? "none"} (${nextCell?.pointCount ?? 0}/2 points)');
}


double _getDistanceToCell(LatLng userLocation, GridCell cell) {
  // Calculate distance to center of cell
  return Geolocator.distanceBetween(
    userLocation.latitude, 
    userLocation.longitude,
    cell.centerLat, 
    cell.centerLon
  );
}

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    print('Map tapped at: ${point.latitude}, ${point.longitude}');
    
    if (_surveyMode == 'manual' && !_isCollecting) {
      _recordMagneticReading();
    }
    
    if (_gridCells.isNotEmpty) {
      for (var cell in _gridCells) {
        if (_isPointInCell(point, cell)) {
          setState(() {
            _currentCell = cell;
            if (cell.status == GridCellStatus.notStarted) {
              cell.status = GridCellStatus.inProgress;
              cell.startTime = DateTime.now();
            }
          });
          break;
        }
      }
    }
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
              child: Text('GPS accuracy is poor. Move to open sky for better signal.'),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Magnetic sensor calibrated successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: Text('Calibrate'),
          ),
        ],
      ),
    );
  }

  void _checkGpsQuality() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No GPS position available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isGpsCalibrated = _gpsAccuracy < 10.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              _isGpsCalibrated ? Icons.check_circle : Icons.warning,
              color: Colors.white,
            ),
            SizedBox(width: 8),
            Text(_isGpsCalibrated 
                ? 'GPS calibration complete!' 
                : 'GPS signal still poor - try moving to open area'),
          ],
        ),
        backgroundColor: _isGpsCalibrated ? Colors.green : Colors.orange,
      ),
    );
  }

  // ==================== SETTINGS ====================

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Settings & Teams'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Survey Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              
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
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              
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
                      Navigator.pop(context);
                    }
                  },
                ),
              ),

              Divider(),
              
              Text('Team Collaboration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              
              SwitchListTile(
                title: Text('Enable Team Mode'),
                subtitle: Text('Collaborate with other surveyors'),
                value: _isTeamMode,
                onChanged: (bool value) {
                  setState(() => _isTeamMode = value);
                  if (value) {
                    _initializeTeamMode();
                  } else {
                    _teamService?.dispose();
                  }
                },
              ),

              if (_isTeamMode) ...[
                ListTile(
                  title: Text('Team Members (${_teamMembers.length})'),
                  subtitle: Text('Tap to manage team'),
                  trailing: Icon(Icons.group),
                  onTap: _showTeamPanel,
                ),
                
                SwitchListTile(
                  title: Text('Show Team on Map'),
                  value: _showTeamMembers,
                  onChanged: (bool value) {
                    setState(() => _showTeamMembers = value);
                  },
                ),
              ],

              Divider(),
              
              Text('Sensor Calibration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 8),
              
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

  String _getBaseLayerName(MapBaseLayer layer) {
    switch (layer) {
      case MapBaseLayer.openStreetMap:
        return 'OpenStreetMap';
      case MapBaseLayer.satellite:
        return 'Satellite';
      case MapBaseLayer.emag2Magnetic:
        return 'EMAG2 Magnetic';
    }
  }

  void _restartAutomaticCollection() {
    if (_isCollecting) {
      _stopAutomaticCollection();
      _startAutomaticCollection();
    }
  }

  // ==================== TEAM FUNCTIONALITY ====================

  void _initializeTeamMode() {
    _teamService = TeamSyncService.instance;
    _teamSubscription = _teamService!.teamMembersStream.listen((members) {
      setState(() {
        _teamMembers = members;
      });
    });
  }

  void _showTeamPanel() {
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
                'Team Management',
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
              ElevatedButton.icon(
                onPressed: _addTeamMember,
                icon: Icon(Icons.person_add),
                label: Text('Add Team Member'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addTeamMember() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Team member invitation feature coming soon!'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _removeTeamMember(TeamMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Team Member'),
        content: Text('Remove ${member.name} from the team?'),
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
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${member.name} removed from team'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ==================== EXPORT FUNCTIONALITY ====================

  void _exportSurveyData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Export Survey Data'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose export format:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Project: ${widget.project?.name ?? "Current Survey"}\nPoints collected: $_pointCount',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              SizedBox(height: 16),
              
              _buildExportFormatButton(ExportFormat.csv, Icons.table_chart, Colors.green),
              SizedBox(height: 8),
              _buildExportFormatButton(ExportFormat.geojson, Icons.map, Colors.blue),
              SizedBox(height: 8),
              _buildExportFormatButton(ExportFormat.kml, Icons.public, Colors.orange),
              if (!_isWebMode) SizedBox(height: 8),
              if (!_isWebMode) _buildExportFormatButton(ExportFormat.sqlite, Icons.storage, Colors.purple),
              SizedBox(height: 8),
              _buildExportFormatButton(ExportFormat.shapefile, Icons.layers, Colors.teal),
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
        onPressed: () => _performExport(format),
        icon: Icon(icon, size: 20),
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getFormatDisplayName(format),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              _getFormatDescription(format),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          alignment: Alignment.centerLeft,
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

  String _getFormatDescription(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        return 'Spreadsheet compatible format';
      case ExportFormat.geojson:
        return 'GIS and web mapping compatible';
      case ExportFormat.kml:
        return 'Google Earth and GPS compatible';
      case ExportFormat.sqlite:
        return 'Complete database backup';
      case ExportFormat.shapefile:
        return 'GIS shapefile format (WKT)';
    }
  }

  Future<void> _performExport(ExportFormat format) async {
    Navigator.pop(context);
    
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Exporting survey data...'),
              SizedBox(height: 8),
              Text(
                'Format: ${_getFormatDisplayName(format)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );

      final project = widget.project ?? SurveyProject(
        name: 'Survey Export',
        description: 'Magnetic survey data export',
        createdAt: DateTime.now(),
      );

      List<MagneticReading> allReadings = List.from(_savedReadings);
      
      for (int i = 0; i < _collectedPoints.length; i++) {
        final point = _collectedPoints[i];
        bool exists = _savedReadings.any((reading) => 
          (reading.latitude - point.latitude).abs() < 0.000001 &&
          (reading.longitude - point.longitude).abs() < 0.000001
        );
        
        if (!exists) {
          allReadings.add(MagneticReading(
            latitude: point.latitude,
            longitude: point.longitude,
            altitude: _currentPosition?.altitude ?? 0.0,
            magneticX: _magneticX,
            magneticY: _magneticY,
            magneticZ: _magneticZ,
            totalField: _totalField,
            timestamp: DateTime.now().subtract(Duration(minutes: i)),
            projectId: project.id ?? 1,
            accuracy: _gpsAccuracy,
            heading: _heading,
          ));
        }
      }

      String exportData = await ExportService.instance.exportProject(
        project: project,
        readings: allReadings,
        gridCells: _gridCells,
        fieldNotes: [],
        format: format,
      );

      Navigator.pop(context);

      String extension = ExportService.instance.getFileExtension(format);
      String sanitizedProjectName = project.name
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w\-_]'), '');
      String filename = '${sanitizedProjectName}_${DateTime.now().millisecondsSinceEpoch}$extension';
      
      await ExportService.instance.saveAndShare(
        data: exportData,
        filename: filename,
        mimeType: ExportService.instance.getMimeType(format),
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Survey data exported as ${_getFormatDisplayName(format)}!'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}