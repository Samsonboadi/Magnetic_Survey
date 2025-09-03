// Enhanced Production Survey Screen with Navigation Icon Fix
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
import 'data_analysis.dart';

enum MapBaseLayer {
  openStreetMap,
  satellite,
  emag2Magnetic,
}

class SurveyScreen extends StatefulWidget {
  final SurveyProject? project;
  final List<GridCell>? initialGridCells;
  final LatLng? gridCenter;
  final int? selectedGridId;

  SurveyScreen({
    this.project,
    this.initialGridCells,
    this.gridCenter,
    this.selectedGridId,
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

  // MAP ORIENTATION AND NAVIGATION ICON FIX VARIABLES
  bool _isMapOrientationEnabled = false;
  double? _lastHeading;
  Timer? _orientationUpdateTimer;
  
  // NAVIGATION ICON FIX - NEW VARIABLES
  bool _rotateIconWithMap = true; // Toggle between icon rotation vs map rotation
  double _deviceHeading = 0.0; // Raw device heading
  double _navigationHeading = 0.0; // Processed heading for navigation
  bool _useStackOverflowFix = true; // Apply the StackOverflow heading correction
  // User preference: tap map to record (default off)
  bool _tapToRecordEnabled = false;

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
  double _magneticStrength = 0.0;

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
  // Hide compass widget by default; no toggle in UI
  bool _showCompass = false;
  bool _autoNavigate = true;
  bool _isCollecting = false;
  bool _isTeamMode = false;
  bool _hasLocationError = false;
  bool _hasSensorError = false;
  bool _needsTargetCellUpdate = false;
  bool _isMapReady = false;
  bool _isTaskBarCollapsed = false;
  bool _followLocation = true;
  String _surveyMode = 'manual';
  MapBaseLayer _currentBaseLayer = MapBaseLayer.openStreetMap;

  // Data collection state tracking
  bool _showDataBanner = false;
  Timer? _bannerHideTimer;

  // Magnetic field color scale constants (microTesla range for smartphones)
  static const double MIN_MAGNETIC_FIELD = 20.0;
  static const double MAX_MAGNETIC_FIELD = 70.0;

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
          
          // Wait for map to be ready before centering
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
            
            // Only auto-follow if enabled AND map is ready
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

  // Helper method to wait for map ready then center
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

  // ENHANCED SENSOR LISTENING WITH NAVIGATION FIX
  void _startSensorListening() {
    if (_isWebMode) {
      // Web simulation for testing
      _simulateDataForWeb();
      return;
    }

    try {
      // Enhanced compass listening with navigation fix
      _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
        if (mounted && event.heading != null) {
          setState(() {
            _deviceHeading = event.heading!;
            
            // Apply the StackOverflow fix for navigation heading
            _navigationHeading = _processNavigationHeading(event.heading!);
            _heading = _navigationHeading;
          });
        }
      });

      // Magnetometer subscription (keep existing functionality)
      _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
        if (mounted) {
          setState(() {
            _magneticX = event.x;
            _magneticY = event.y;
            _magneticZ = event.z;
            _magneticStrength = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
            _totalField = _magneticStrength;
          });
        }
      });
    } catch (e) {
      print('Sensor error: $e');
      setState(() {
        _hasSensorError = true;
      });
    }
  }

  // NAVIGATION HEADING PROCESSING - SIMPLIFIED FOR REAL MAP ROTATION
  double _processNavigationHeading(double rawHeading) {
    // For real-time map rotation like Google Maps, we want smooth, responsive updates
    // Only apply corrections if specifically needed for your device
    
    if (_rotateIconWithMap) {
      // For icon rotation: apply StackOverflow fix if the icon points wrong way
      if (_useStackOverflowFix) {
        double correctedHeading = -rawHeading;
        while (correctedHeading < 0) correctedHeading += 360;
        while (correctedHeading >= 360) correctedHeading -= 360;
        return correctedHeading;
      }
      return rawHeading;
    } else {
      // For map rotation: use raw heading for natural rotation
      // This makes the map rotate to match your facing direction
      return rawHeading;
    }
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

  void _simulateDataForWeb() {
    _webSimulationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) {
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
        _isGpsCalibrated = _gpsAccuracy < 5.0;
        _isMagneticCalibrated = true;
      });
    });
  }

  // ==================== MAP ORIENTATION METHODS ====================

  void _toggleMapOrientation() {
    setState(() {
      _isMapOrientationEnabled = !_isMapOrientationEnabled;
    });

    if (_isMapOrientationEnabled) {
      // Start real-time orientation updates
      _startMapOrientationUpdates();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🧭 Map now rotates to match your facing direction - like Google Maps navigation!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      // Stop orientation updates and reset to north
      _stopMapOrientationUpdates();
      _resetMapToNorth();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Map rotation disabled - Map reset to north-up'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _startMapOrientationUpdates() {
    _orientationUpdateTimer?.cancel();
    // Faster, smoother updates for full rotation responsiveness
    _orientationUpdateTimer = Timer.periodic(Duration(milliseconds: 250), (timer) {
      if (_heading != null && _isMapOrientationEnabled && _isMapReady) {
        // Update more frequently for smoother rotation (reduced threshold)
        if (_lastHeading == null || (_heading! - _lastHeading!).abs() > 2.0) {
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

  // ENHANCED MAP ROTATION - REAL-TIME ROTATION BASED ON DEVICE ORIENTATION
  void _updateMapRotation(double heading) {
    // Only rotate map if we're NOT rotating the icon instead
    if (_rotateIconWithMap) {
      return; // Don't rotate map when icon rotates
    }
    
    try {
      // Normalize heading to 0..360 for consistent full rotation
      double h = heading % 360.0;
      if (h < 0) h += 360.0;
      // FIXED: For true Google Maps-style navigation rotation
      // The map should rotate so that your facing direction is always "up"
      // Convert heading to radians for map rotation
      double rotationRadians = -h * (math.pi / 180.0); // Negative for correct rotation direction
      
      // Get current camera position
      final currentCamera = _mapController.camera;
      
      // Use moveAndRotate for smooth rotation transition
      _mapController.moveAndRotate(
        currentCamera.center, // Keep same center position
        currentCamera.zoom,   // Keep same zoom level
        rotationRadians,      // Apply rotation
      );
      
      if (kDebugMode) {
        print('Map rotated to heading: ${h.toStringAsFixed(1)}°, map rotation: ${rotationRadians.toStringAsFixed(3)} radians');
      }
    } catch (e) {
      print('Error updating map rotation: $e');
      // Fallback: try simple rotation
      try {
        double h = heading % 360.0; if (h < 0) h += 360.0;
        double rotationRadians = -h * (math.pi / 180.0);
        _mapController.rotate(rotationRadians);
      } catch (fallbackError) {
        print('Fallback rotation also failed: $fallbackError');
      }
    }
  }

  // void _startMapOrientationUpdates() {
  //   _orientationUpdateTimer?.cancel();
  //   _orientationUpdateTimer = Timer.periodic(Duration(milliseconds: 500), (timer) { // Faster updates for smoother rotation
  //     if (_heading != null && _isMapOrientationEnabled && _isMapReady) {
  //       // Update more frequently for smoother rotation (reduced threshold)
  //       if (_lastHeading == null || (_heading! - _lastHeading!).abs() > 5.0) { // Reduced from 10 to 5 degrees
  //         _updateMapRotation(_heading!);
  //         _lastHeading = _heading;
  //       }
  //     }
  //   });
  // }

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

  // ==================== NAVIGATION ICON METHODS ====================

  // Enhanced location marker with proper rotation handling
  Widget _buildLocationMarker() {
    if (_currentPosition == null) return SizedBox.shrink();
    
    return MarkerLayer(
      markers: [
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          child: _buildNavigationIcon(),
        ),
      ],
    );
  }

  // Navigation icon builder with rotation options
  Widget _buildNavigationIcon() {
    if (_rotateIconWithMap) {
      // Option 1: Rotate icon based on heading, keep map fixed
      return Container(
        width: 30,
        height: 30,
        child: Transform.rotate(
          angle: (_navigationHeading) * math.pi / 180, // Rotate icon based on processed heading
          child: _buildIconShape(),
        ),
      );
    } else {
      // Option 2: Keep icon pointing "up" on screen, let map rotate instead
      return Container(
        width: 30,
        height: 30,
        child: _buildIconShape(), // Icon stays pointing "up" on screen
      );
    }
  }

  // Navigation icon shape (the actual icon design)
  Widget _buildIconShape() {
    return Container(
      decoration: BoxDecoration(
        color: _isGpsCalibrated ? Colors.blue : Colors.orange,
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
      child: Icon(
        Icons.navigation, // Arrow-like icon that shows direction
        color: Colors.white,
        size: 16,
      ),
    );
  }

  // ==================== NAVIGATION MODE TOGGLES ====================

  // Toggle between icon rotation and map rotation modes
  void _toggleNavigationMode() {
    setState(() {
      _rotateIconWithMap = !_rotateIconWithMap;
    });
    
    if (!_rotateIconWithMap) {
      // If switching to map rotation mode, enable map orientation
      if (!_isMapOrientationEnabled) {
        _toggleMapOrientation();
      }
    } else {
      // If switching to icon rotation mode, disable map orientation
      if (_isMapOrientationEnabled) {
        _toggleMapOrientation();
      }
      // Reset map to north when switching to icon rotation mode
      _resetMapToNorth();
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_rotateIconWithMap 
            ? 'Icon rotates with heading - Map stays north-up' 
            : 'Map rotates in real-time to match your facing direction'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Toggle the StackOverflow fix on/off for testing
  void _toggleStackOverflowFix() {
    setState(() {
      _useStackOverflowFix = !_useStackOverflowFix;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_useStackOverflowFix 
            ? 'StackOverflow heading fix enabled' 
            : 'StackOverflow heading fix disabled - using raw compass data'),
        backgroundColor: _useStackOverflowFix ? Colors.green : Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Navigation mode toggle button
  Widget _buildNavigationModeToggle() {
    return FloatingActionButton.small(
      heroTag: "navigation_mode",
      onPressed: _toggleNavigationMode,
      backgroundColor: _rotateIconWithMap ? Colors.green : Colors.purple,
      child: Icon(
        _rotateIconWithMap ? Icons.screen_rotation : Icons.map,
        color: Colors.white,
        size: 20,
      ),
      tooltip: _rotateIconWithMap 
          ? 'Switch to Map Rotation Mode' 
          : 'Switch to Icon Rotation Mode',
    );
  }

  // StackOverflow fix toggle button (for testing)
  Widget _buildStackOverflowFixToggle() {
    return FloatingActionButton.small(
      heroTag: "stackoverflow_fix",
      onPressed: _toggleStackOverflowFix,
      backgroundColor: _useStackOverflowFix ? Colors.teal : Colors.grey,
      child: Icon(
        _useStackOverflowFix ? Icons.auto_fix_high : Icons.auto_fix_off,
        color: Colors.white,
        size: 18,
      ),
      tooltip: _useStackOverflowFix 
          ? 'Disable StackOverflow Fix' 
          : 'Enable StackOverflow Fix',
    );
  }

  // ==================== DATA RECORDING ====================

  Future<void> _recordMagneticReading() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Waiting for GPS signal...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final reading = MagneticReading(
        projectId: widget.project?.id ?? 0,
        gridId: widget.selectedGridId,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        magneticX: _magneticX - _magneticCalibrationX,
        magneticY: _magneticY - _magneticCalibrationY,
        magneticZ: _magneticZ - _magneticCalibrationZ,
        totalField: _totalField,
        altitude: _currentPosition!.altitude,
        accuracy: _currentPosition!.accuracy,
        timestamp: DateTime.now(),
        heading: _heading,
      );

      if (!_isWebMode) {
        await DatabaseService.instance.insertMagneticReading(reading);
      }

      setState(() {
        _savedReadings.add(reading);
        _collectedPoints.add(LatLng(reading.latitude, reading.longitude));
        _pointCount++;
      });

      _updateCoverageStats();
      _showTemporaryDataBanner();

      if (kDebugMode) {
        print('Recorded: ${reading.totalField.toStringAsFixed(2)}μT at ${reading.latitude.toStringAsFixed(6)}, ${reading.longitude.toStringAsFixed(6)}');
      }

    } catch (e) {
      print('Error recording reading: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

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
    _automaticCollectionTimer?.cancel();
    _automaticCollectionTimer = Timer.periodic(_magneticPullRate, (timer) {
      if (mounted && _isCollecting) {
        _recordMagneticReading();
      }
    });
  }

  void _stopAutomaticCollection() {
    _automaticCollectionTimer?.cancel();
    _automaticCollectionTimer = null;
  }

  void _updateCoverageStats() {
    if (_gridCells.isNotEmpty) {
      int completed = _gridCells.where((cell) => cell.status == GridCellStatus.completed).length;
      setState(() {
        _completedCells = completed;
        _coveragePercentage = (completed / _gridCells.length) * 100;
      });
    }
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

  // ==================== UI BUILD METHODS ====================

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
          
          // FIXED: Location follow toggle button - moved to avoid legend
          Positioned(
            top: 70, // Moved down to avoid magnetic scale
            right: 10,
            child: _buildLocationFollowButton(),
          ),
          
          // FIXED: Magnetic scale legend - moved to avoid covering location icon
          Positioned(
            top: 10,
            right: 10,
            child: _buildHorizontalMagneticScale(),
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
        maxZoom: 20.0,
        minZoom: 8.0,
        onMapReady: () {
          setState(() {
            _isMapReady = true;
          });
        },
        onTap: (tapPosition, point) {
          print('Map tapped at: ${point.latitude}, ${point.longitude}');
          if (_tapToRecordEnabled && _surveyMode == 'manual' && !_isCollecting) {
            _recordMagneticReading();
          }
        },
      ),
      children: [
        _buildBaseMapLayer(),
        
        // Grid overlay
        if (_showGrid && _gridCells.isNotEmpty)
          PolygonLayer(
            polygons: _gridCells.map((cell) => Polygon(
              points: cell.bounds,
              color: _getCellColor(cell.status).withOpacity(0.2),
              borderColor: _getCellColor(cell.status),
              borderStrokeWidth: 2.0,
            )).toList(),
          ),
        
        // Saved readings layer
        if (_savedReadings.isNotEmpty)
          CircleLayer(
            circles: _savedReadings.map((reading) => CircleMarker(
              point: LatLng(reading.latitude, reading.longitude),
              radius: 4,
              color: _getMagneticFieldColor(reading.totalField),
              borderColor: Colors.white,
              borderStrokeWidth: 1,
            )).toList(),
          ),
        
        // Collected points layer
        CircleLayer(
          circles: _collectedPoints.map((point) => CircleMarker(
            point: point,
            radius: 3,
            color: Colors.green,
            borderColor: Colors.white,
            borderStrokeWidth: 1,
          )).toList(),
        ),

        // ENHANCED LOCATION MARKER WITH NAVIGATION FIX
        _buildLocationMarker(),

        // Team members layer
        if (_isTeamMode && _showTeamMembers)
          MarkerLayer(
            markers: _teamMembers.map((member) => Marker(
              point: member.currentPosition ?? LatLng(0, 0),
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
            )).where((marker) => (marker.point.latitude != 0 || marker.point.longitude != 0)).toList(),
          ),
      ],
    );
  }

  LatLng _getInitialMapCenter() {
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    if (widget.gridCenter != null) {
      return widget.gridCenter!;
    }
    return LatLng(0.0, 0.0); // Default fallback
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

  Color _getCellColor(GridCellStatus status) {
    switch (status) {
      case GridCellStatus.notStarted:
        return Colors.blue;
      case GridCellStatus.inProgress:
        return Colors.orange;
      case GridCellStatus.completed:
        return Colors.green;
    }
  }

  Color _getMagneticFieldColor(double field) {
    // FIXED: Correct range 20-70 μT for smartphone magnetometers
    double normalizedField = (field - MIN_MAGNETIC_FIELD) / (MAX_MAGNETIC_FIELD - MIN_MAGNETIC_FIELD);
    normalizedField = normalizedField.clamp(0.0, 1.0);
    
    // Enhanced color mapping for better visualization
    if (normalizedField < 0.2) {
      // 20-30 μT: Blue to Cyan
      double t = normalizedField / 0.2;
      return Color.lerp(Colors.blue, Colors.cyan, t)!;
    } else if (normalizedField < 0.5) {
      // 30-45 μT: Cyan to Green
      double t = (normalizedField - 0.2) / 0.3;
      return Color.lerp(Colors.cyan, Colors.green, t)!;
    } else if (normalizedField < 0.7) {
      // 45-55 μT: Green to Yellow
      double t = (normalizedField - 0.5) / 0.2;
      return Color.lerp(Colors.green, Colors.yellow, t)!;
    } else if (normalizedField < 0.85) {
      // 55-60 μT: Yellow to Orange
      double t = (normalizedField - 0.7) / 0.15;
      return Color.lerp(Colors.yellow, Colors.orange, t)!;
    } else {
      // 60-70 μT: Orange to Red
      double t = (normalizedField - 0.85) / 0.15;
      return Color.lerp(Colors.orange, Colors.red, t)!;
    }
  }

  PreferredSizeWidget _buildMinimalAppBar() {
    return AppBar(
      title: Text(
        widget.project?.name ?? 'Survey Session',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      backgroundColor: Colors.blue[800],
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: Icon(Icons.analytics),
          tooltip: 'Data Analysis',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DataAnalysisScreen(
                  readings: List.from(_savedReadings),
                  project: widget.project,
                ),
              ),
            );
          },
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
            color: _isGpsCalibrated ? Colors.green.withOpacity(0.9) : Colors.orange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gps_fixed, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                'GPS: ±${_gpsAccuracy.toStringAsFixed(1)}m',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ),
        
        SizedBox(height: 8),
        
        // Magnetic Status
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isMagneticCalibrated ? Colors.purple.withOpacity(0.9) : Colors.grey.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sensors, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                '${_totalField.toStringAsFixed(1)}μT',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ),
        // Compass widget removed from UI for cleaner layout
      ],
    );
  }

  Widget _buildLocationFollowButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _followLocation = !_followLocation;
        });
        
        // Immediately center on current location when enabled
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

  // FIXED: Horizontal magnetic scale in top right corner
  Widget _buildHorizontalMagneticScale() {
    const double minField = 20.0;
    const double midField = 45.0;
    const double maxField = 70.0;

    double value = _totalField.isFinite ? _totalField : midField;
    double normalized = ((value - minField) / (maxField - minField)).clamp(0.0, 1.0);

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
      ),
      padding: EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final barHeight = 6.0;
              final indicatorSize = 8.0;
              return Column(
                children: [
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Gradient bar
                      SizedBox(
                        height: barHeight,
                        width: constraints.maxWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(barHeight / 2),
                            gradient: LinearGradient(
                              colors: [
                                Colors.blue,
                                Colors.cyan,
                                Colors.green,
                                Colors.yellow,
                                Colors.orange,
                                Colors.red,
                              ],
                              stops: [0.0, 0.3, 0.5, 0.7, 0.85, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Moving indicator
                      AnimatedPositioned(
                        duration: Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        left: (constraints.maxWidth - indicatorSize) * normalized,
                        child: Container(
                          width: indicatorSize,
                          height: indicatorSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                            border: Border.all(color: Colors.black12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${minField.toStringAsFixed(0)}', style: TextStyle(fontSize: 8, color: Colors.black54)),
                      Text('${midField.toStringAsFixed(0)}', style: TextStyle(fontSize: 8, color: Colors.black54)),
                      Text('${maxField.toStringAsFixed(0)}', style: TextStyle(fontSize: 8, color: Colors.black54)),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // Remove the old _buildMagneticScale method since we're using the horizontal one

  // FIXED: Compass widget with correct rotation direction
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
        angle: (_heading ?? 0) * math.pi / 180, // FIXED: Remove negative sign to fix upside down issue
        child: CustomPaint(
          painter: SurveyCompassPainter(),
          size: Size(80, 80),
        ),
      ),
    );
  }

  Widget _buildCollapsibleTaskBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0.0, 0.0),
          end: Offset(0.0, 1.0),
        ).animate(_taskBarAnimation),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
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
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Survey Stats',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        _isTaskBarCollapsed 
                            ? Icons.keyboard_arrow_up 
                            : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                        size: 18,
                      ),
                    ],
                  ),
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

  // ENHANCED FLOATING ACTION BUTTONS WITH NAVIGATION CONTROLS
  Widget _buildFloatingActionButtons() {
    // Simplified FABs: only map orientation, manual record, and auto record
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Map orientation button (auto-switches to Map Rotation mode if needed)
        FloatingActionButton.small(
          heroTag: "map_orientation",
          onPressed: () {
            if (_rotateIconWithMap) {
              // Auto-switch to Map Rotation mode and enable orientation
              _toggleNavigationMode();
            } else {
              // Toggle orientation within Map Rotation mode
              _toggleMapOrientation();
            }
          },
          backgroundColor: _rotateIconWithMap
              ? Colors.purple // Indicate action available even in icon mode
              : (_isMapOrientationEnabled ? Colors.deepPurple : Colors.grey),
          child: Icon(
            (!_rotateIconWithMap && _isMapOrientationEnabled)
                ? Icons.explore
                : Icons.explore_outlined,
            color: Colors.white,
            size: 20,
          ),
          tooltip: _rotateIconWithMap
              ? 'Enable Map Rotation (switch mode)'
              : (_isMapOrientationEnabled
                  ? 'Disable Map Orientation'
                  : 'Enable Map Orientation'),
        ),

        SizedBox(height: 12),

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
            color: Colors.white,
          ),
          tooltip: _isCollecting ? 'Stop Auto Recording' : 'Start Auto Recording',
        ),
      ],
    );
  }

  // ==================== SETTINGS AND DIALOGS ====================

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text('Survey Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),

                  // Navigation
                  Text('Navigation', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.black12)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.navigation),
                          title: Text('Navigation Mode'),
                          subtitle: Text(_rotateIconWithMap ? 'Icon Rotation' : 'Map Rotation'),
                          trailing: ToggleButtons(
                            isSelected: [_rotateIconWithMap, !_rotateIconWithMap],
                            onPressed: (index) {
                              final wantMapMode = index == 1;
                              if (wantMapMode != !_rotateIconWithMap) {
                                _toggleNavigationMode();
                              }
                            },
                            constraints: BoxConstraints(minHeight: 36, minWidth: 40),
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.screen_rotation),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.map),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 0),
                        ListTile(
                          leading: Icon(Icons.auto_fix_high),
                          title: Text('Heading Correction'),
                          subtitle: Text(_useStackOverflowFix ? 'StackOverflow Fix Applied' : 'Raw Compass Data'),
                          trailing: Switch(
                            value: _useStackOverflowFix,
                            onChanged: (value) => _toggleStackOverflowFix(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 12),
                  Text('Map', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.black12)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.map),
                          title: Text('Base Layer'),
                          subtitle: Text(_getMapLayerName()),
                          onTap: _showMapLayerDialog,
                          trailing: DropdownButton<MapBaseLayer>(
                            value: _currentBaseLayer,
                            underline: SizedBox.shrink(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _currentBaseLayer = value);
                            },
                            items: MapBaseLayer.values.map((layer) => DropdownMenuItem(
                              value: layer,
                              child: Text(_getLayerDisplayName(layer)),
                            )).toList(),
                          ),
                        ),
                        Divider(height: 0),
                        ListTile(
                          leading: Icon(Icons.grid_on),
                          title: Text('Show Grid'),
                          trailing: Switch(
                            value: _showGrid,
                            onChanged: (value) => setState(() => _showGrid = value),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 12),
                  Text('Data Collection', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.black12)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.timer),
                          title: Text('Collection Interval'),
                          trailing: DropdownButton<int>(
                            value: _magneticPullRate.inSeconds,
                            underline: SizedBox.shrink(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _magneticPullRate = Duration(seconds: value));
                            },
                            items: [1,2,5,10].map((s) => DropdownMenuItem(value: s, child: Text('${s}s'))).toList(),
                          ),
                          onTap: _showIntervalDialog, // still available
                        ),
                        Divider(height: 0),
                        ListTile(
                          leading: Icon(Icons.touch_app),
                          title: Text('Tap Map To Record'),
                          subtitle: Text(_tapToRecordEnabled ? 'Enabled' : 'Disabled'),
                          trailing: Switch(
                            value: _tapToRecordEnabled,
                            onChanged: (value) => setState(() => _tapToRecordEnabled = value),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showCalibrationDialog,
                          icon: Icon(Icons.settings_input_component),
                          label: Text('Calibrate Sensors'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_isMagneticCalibrated && _isGpsCalibrated) ? Colors.green : Colors.orange,
                            foregroundColor: Colors.white,
                            minimumSize: Size.fromHeight(44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _exportSurveyData,
                          icon: Icon(Icons.download),
                          label: Text('Export Data'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: Size.fromHeight(44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _getMapLayerName() {
    switch (_currentBaseLayer) {
      case MapBaseLayer.openStreetMap:
        return 'OpenStreetMap';
      case MapBaseLayer.satellite:
        return 'Satellite';
      case MapBaseLayer.emag2Magnetic:
        return 'EMAG2 Magnetic';
    }
  }

  void _showMapLayerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose Map Layer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: MapBaseLayer.values.map((layer) => RadioListTile<MapBaseLayer>(
            title: Text(_getLayerDisplayName(layer)),
            value: layer,
            groupValue: _currentBaseLayer,
            onChanged: (value) {
              setState(() {
                _currentBaseLayer = value!;
              });
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  String _getLayerDisplayName(MapBaseLayer layer) {
    switch (layer) {
      case MapBaseLayer.openStreetMap:
        return 'Standard Map';
      case MapBaseLayer.satellite:
        return 'Satellite Imagery';
      case MapBaseLayer.emag2Magnetic:
        return 'Magnetic Anomaly';
    }
  }

  void _showIntervalDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Collection Interval'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [1, 2, 5, 10].map((seconds) => RadioListTile<int>(
            title: Text('${seconds}s'),
            value: seconds,
            groupValue: _magneticPullRate.inSeconds,
            onChanged: (value) {
              setState(() {
                _magneticPullRate = Duration(seconds: value!);
              });
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showCalibrationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sensor Calibration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_input_component, size: 64, color: Colors.blue),
            SizedBox(height: 16),
            Text('For best results:'),
            SizedBox(height: 8),
            Text('• Move away from metal objects'),
            Text('• Hold device away from body'),
            Text('• Ensure good GPS signal'),
            SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  _isGpsCalibrated ? Icons.check_circle : Icons.warning,
                  color: _isGpsCalibrated ? Colors.green : Colors.orange,
                ),
                SizedBox(width: 8),
                Text('GPS: ${_gpsAccuracy.toStringAsFixed(1)}m accuracy'),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _isMagneticCalibrated ? Icons.check_circle : Icons.warning,
                  color: _isMagneticCalibrated ? Colors.green : Colors.orange,
                ),
                SizedBox(width: 8),
                Text('Magnetic: ${_isMagneticCalibrated ? "Calibrated" : "Not Calibrated"}'),
              ],
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
              setState(() {
                _magneticCalibrationX = _magneticX;
                _magneticCalibrationY = _magneticY;
                _magneticCalibrationZ = _magneticZ;
                _isMagneticCalibrated = true;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sensors calibrated successfully!'),
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
              Text('Navigation Controls:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Use Settings to choose Icon vs Map rotation'),
              Text('• Map button: Enable/disable map auto-rotation'),
              SizedBox(height: 16),
              
              Text('Getting Started:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. Calibrate sensors using the calibrate button'),
              Text('2. Wait for good GPS signal (green status)'),
              Text('3. Choose navigation mode (icon vs map rotation)'),
              Text('4. Use manual recording or start automatic mode'),
              SizedBox(height: 16),
              
              Text('Recording Data:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Green FAB: Record single point'),
              Text('• Blue FAB: Start/stop automatic recording'),
              Text('• Enable "Tap Map To Record" in Settings if desired'),
              SizedBox(height: 16),
              
              Text('Map Controls:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Pinch to zoom in/out'),
              Text('• Drag to move map'),
              Text('• Grid shows survey boundaries'),
              Text('• Colored dots show recorded magnetic data'),
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
                'Project: ${widget.project?.name ?? "Current Session"}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              Text(
                'Points: $_pointCount',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              SizedBox(height: 16),
              
              ListTile(
                leading: Icon(Icons.table_chart),
                title: Text('CSV Format'),
                subtitle: Text('Spreadsheet compatible'),
                onTap: () => _performExport(ExportFormat.csv),
              ),
              ListTile(
                leading: Icon(Icons.map),
                title: Text('GeoJSON'),
                subtitle: Text('GIS compatible format'),
                onTap: () => _performExport(ExportFormat.geojson),
              ),
              ListTile(
                leading: Icon(Icons.public),
                title: Text('Google Earth KML'),
                subtitle: Text('View in Google Earth'),
                onTap: () => _performExport(ExportFormat.kml),
              ),
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

  Future<void> _performExport(ExportFormat format) async {
    Navigator.pop(context); // Close dialog
    
    try {
      if (_savedReadings.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No data to export'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      String exportData = await ExportService.instance.exportProject(
        project: widget.project ?? SurveyProject(
          name: 'Current Session',
          description: 'Live survey session',
          createdAt: DateTime.now(),
        ),
        readings: _savedReadings,
        gridCells: _gridCells,
        fieldNotes: [],
        format: format,
      );
      
      if (kIsWeb) {
        // Web: show data in dialog
        _showExportDialog(exportData, format);
      } else {
        // Mobile: use share
        String filename = 'survey_${DateTime.now().millisecondsSinceEpoch}${ExportService.instance.getFileExtension(format)}';
        await ExportService.instance.saveAndShare(
          data: exportData,
          filename: filename,
          mimeType: ExportService.instance.getMimeType(format),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Remove the old _getFileExtension method since we're using ExportService.instance.getFileExtension() now

  void _showExportDialog(String data, ExportFormat format) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Export Data'),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              data,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
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

  // ==================== UTILITY METHODS ====================

  bool _isPointInCell(LatLng point, GridCell cell) {
    // Simple polygon point-in-polygon test using Dart-compatible for loop
    bool c = false;
    List<LatLng> vertices = cell.bounds;
    
    for (int i = 0, j = vertices.length - 1; i < vertices.length; j = i, i++) {
      if (((vertices[i].latitude > point.latitude) != (vertices[j].latitude > point.latitude)) &&
          (point.longitude < (vertices[j].longitude - vertices[i].longitude) * 
           (point.latitude - vertices[i].latitude) / 
           (vertices[j].latitude - vertices[i].latitude) + vertices[i].longitude)) {
        c = !c;
      }
    }
    return c;
  }

  double _getDistanceToCell(LatLng userLocation, GridCell cell) {
    return Geolocator.distanceBetween(
      userLocation.latitude, 
      userLocation.longitude,
      cell.centerLat, 
      cell.centerLon
    );
  }

  void _findNextTargetCell() {
    if (_gridCells.isEmpty || _currentPosition == null) return;

    LatLng userLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    
    GridCell? nearestIncomplete = null;
    double nearestDistance = double.infinity;
    
    for (var cell in _gridCells) {
      if (cell.status != GridCellStatus.completed) {
        double distance = _getDistanceToCell(userLocation, cell);
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestIncomplete = cell;
        }
      }
    }
    
    setState(() {
      _nextTargetCell = nearestIncomplete;
    });
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

  String _getTargetCellInfo() {
    if (_nextTargetCell == null) return "No target";
    final nextCell = _nextTargetCell!;
    return "${nextCell.id ?? "none"} (${nextCell.pointCount ?? 0}/2 points)";
  }

  // ==================== TEAM MANAGEMENT ====================

  void _showTeamDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Team Management'),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: Column(
            children: [
              Text('Team Members (${_teamMembers.length})'),
              SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _teamMembers.length,
                  itemBuilder: (context, index) {
                    final member = _teamMembers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: member.markerColor,
                        child: Icon(Icons.person, color: Colors.white, size: 16),
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
    setState(() {
      _teamMembers.remove(member);
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${member.name} removed from team'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // ==================== ADDITIONAL UI COMPONENTS ====================

  Widget _buildControlPanel() {
    return Container(
      padding: EdgeInsets.all(12),
      color: Colors.grey[100],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _toggleAutomaticCollection,
                  icon: Icon(_isCollecting ? Icons.stop : Icons.play_arrow),
                  label: Text(_isCollecting ? 'Stop Auto' : 'Start Auto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCollecting ? Colors.red : Colors.blue,
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
                      backgroundColor: _showTeamMembers ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showTeamDialog,
                    icon: Icon(Icons.people),
                    label: Text('Team (${_teamMembers.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
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

  Widget _buildBottomStatsBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomStatItem('Points', _pointCount.toString(), Icons.location_on),
          _buildBottomStatItem('Field', '${_totalField.toStringAsFixed(1)}μT', Icons.sensors),
          _buildBottomStatItem('GPS', '±${_gpsAccuracy.toStringAsFixed(1)}m', Icons.gps_fixed),
          _buildBottomStatItem('Coverage', '${_coveragePercentage.toStringAsFixed(1)}%', Icons.grid_on),
        ],
      ),
    );
  }

  Widget _buildBottomStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.blue[700]),
        SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

// ==================== COMPASS PAINTER ====================

class SurveyCompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    
    // Compass background
    final backgroundPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, backgroundPaint);
    
    // Compass border
    final borderPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);
    
    // North arrow
    final arrowPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    final arrowPath = Path();
    arrowPath.moveTo(center.dx, center.dy - radius + 10);
    arrowPath.lineTo(center.dx - 8, center.dy - radius + 25);
    arrowPath.lineTo(center.dx + 8, center.dy - radius + 25);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);
    
    // North label
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas, 
      Offset(center.dx - textPainter.width / 2, center.dy - radius + 28)
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
