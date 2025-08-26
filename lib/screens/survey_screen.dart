// Enhanced Production Survey Screen with all requested improvements
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
  bool _showTeamMembers = false; // Changed to false for cleaner map
  bool _showCompass = true;
  bool _autoNavigate = true;
  bool _isCollecting = false;
  bool _isTeamMode = false;
  bool _hasLocationError = false;
  bool _needsTargetCellUpdate = false;
  bool _isMapReady = false;
  bool _isTaskBarCollapsed = false; // New: Collapsible taskbar
  bool _followLocation = true; // New: Auto-follow location
  String _surveyMode = 'manual';
  MapBaseLayer _currentBaseLayer = MapBaseLayer.openStreetMap;

  // Data collection state tracking
  bool _showDataBanner = false;
  Timer? _bannerHideTimer;

  // Magnetic field color scale constants (nanoTesla)
  static const double MIN_MAGNETIC_FIELD = 53814.0;
  static const double MAX_MAGNETIC_FIELD = 56767.0;

  // Settings
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

  // Team service
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

    _initializeSurvey();
    _startLocationListening();
    _startSensorListening();
    
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
    super.dispose();
  }

  void _initializeSurvey() {
    // Initialize grid cells if provided
    if (widget.initialGridCells != null) {
      _gridCells = List.from(widget.initialGridCells!);
      _showGrid = true; // Ensure grid is visible
      _findNextTargetCell();
      print('Grid initialized with ${_gridCells.length} cells');
      
      // Set flag to navigate to grid center when map is ready
      _needsTargetCellUpdate = true;
    } else {
      print('No grid provided to survey screen');
    }
    
    if (!_isWebMode && widget.project != null) {
      _loadExistingReadings();
    }
  }

  void _loadExistingReadings() async {
    try {
      final readings = await DatabaseService.instance.getReadingsForProject(widget.project!.id!);
      setState(() {
        _savedReadings = readings;
        _updateCoverageStats();
      });
    } catch (e) {
      print('Error loading readings: $e');
    }
  }

  // ==================== LOCATION & SENSOR MANAGEMENT ====================
  
  void _startLocationListening() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _hasLocationError = true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _hasLocationError = true);
          return;
        }
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
            _isGpsCalibrated = position.accuracy < 10.0;
            _hasLocationError = false;
          });

          if (_isMapReady) {
            final currentLocation = LatLng(position.latitude, position.longitude);
            
            if (_autoNavigate && _gridCells.isNotEmpty) {
              try {
                final gridBounds = _calculateGridBounds();
                if (gridBounds != null) {
                  final userInGrid = _isPositionInBounds(currentLocation, gridBounds);
                  
                  if (!userInGrid) {
                    final bounds = LatLngBounds.fromPoints([currentLocation, gridBounds.center]);
                    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(50)));
                  }
                } else {
                  _mapController.move(currentLocation, _mapController.camera.zoom);
                }
              } catch (e) {
                print('Map controller not ready for auto-navigation: $e');
              }
            }
          
            if (_isTeamMode) {
              _teamService?.updateMyPosition(
                LatLng(position.latitude, position.longitude), 
                _heading
              );
            }
          }
        }
      });
    } catch (e) {
      print('Location error: $e');
      _hasLocationError = true;
    }
  }

  void _startSensorListening() {
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      if (mounted) {
        setState(() {
          _magneticX = event.x - _magneticCalibrationX;
          _magneticY = event.y - _magneticCalibrationY;
          _magneticZ = event.z - _magneticCalibrationZ;
          // Use correct total field calculation
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
        // Use correct total field calculation
        _totalField = math.sqrt(_magneticX * _magneticX + _magneticY * _magneticY + _magneticZ * _magneticZ);
        _heading = (math.Random().nextDouble() * 360);
        _gpsAccuracy = 2.0 + math.Random().nextDouble() * 3;
      });
    });
  }

  // ==================== MAGNETIC FIELD COLOR MAPPING ====================
  
  Color getMagneticFieldColor(double totalField) {
    // Normalize the value between 0 and 1
    double normalized = (totalField - MIN_MAGNETIC_FIELD) / (MAX_MAGNETIC_FIELD - MIN_MAGNETIC_FIELD);
    normalized = math.max(0.0, math.min(1.0, normalized)); // Clamp between 0 and 1
    
    // Create spectral color mapping (blue -> cyan -> green -> yellow -> red)
    if (normalized < 0.25) {
      // Blue to Cyan
      double t = normalized / 0.25;
      return Color.lerp(Colors.blue[900]!, Colors.cyan, t)!;
    } else if (normalized < 0.5) {
      // Cyan to Green
      double t = (normalized - 0.25) / 0.25;
      return Color.lerp(Colors.cyan, Colors.green, t)!;
    } else if (normalized < 0.75) {
      // Green to Yellow
      double t = (normalized - 0.5) / 0.25;
      return Color.lerp(Colors.green, Colors.yellow, t)!;
    } else {
      // Yellow to Red
      double t = (normalized - 0.75) / 0.25;
      return Color.lerp(Colors.yellow, Colors.red[900]!, t)!;
    }
  }

  // ==================== DATA COLLECTION ====================

  void _recordMagneticReading() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Waiting for GPS position...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final collectPoint = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    
    setState(() {
      _collectedPoints.add(collectPoint);
      _pointCount = _collectedPoints.length;
    });

    final reading = MagneticReading(
      id: null,
      projectId: widget.project?.id ?? 1,
      latitude: collectPoint.latitude,
      longitude: collectPoint.longitude,
      altitude: _currentPosition!.altitude,
      magneticX: _magneticX,
      magneticY: _magneticY,
      magneticZ: _magneticZ,
      totalField: _totalField,
      timestamp: DateTime.now(),
      accuracy: _currentPosition!.accuracy,
      heading: _heading,
      notes: 'Auto/Manual collection',
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
    
    // Show temporary data banner (improved version)
    _showTemporaryDataBanner();
  }

  void _showTemporaryDataBanner() {
    setState(() {
      _showDataBanner = true;
    });
    
    // Hide banner after 3 seconds
    _bannerHideTimer?.cancel();
    _bannerHideTimer = Timer(Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showDataBanner = false;
        });
      }
    });
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

  // ==================== UI COMPONENTS ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildMinimalAppBar(),
      body: Stack(
        children: [
          // Full screen map
          _buildFullScreenMapView(),
          
          // Floating GPS/Mag status widgets
          Positioned(
            top: 10,
            left: 10,
            child: _buildFloatingStatusWidgets(),
          ),
          
          // Location follow toggle button (moved to avoid overlap)
          Positioned(
            top: 80, // Moved below the magnetic scale
            right: 10,
            child: _buildLocationFollowButton(),
          ),
          
          // Floating magnetic scale legend
          Positioned(
            top: 10,
            right: 10,
            child: _buildMagneticScale(),
          ),
          
          // Collapsible task bar (now floating)
          _buildCollapsibleTaskBar(),
          
          // Temporary data collection banner
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

  Widget _buildLocationFollowButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _followLocation = !_followLocation;
        });
        
        if (_followLocation && _currentPosition != null && _isMapReady) {
          // Immediately center on current location when enabled
          LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
          _mapController.move(currentLocation, _mapController.camera.zoom);
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

  Widget _buildFullScreenMapView() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _getInitialMapCenter(),
        initialZoom: _currentPosition != null ? 16.0 : 10.0,
        minZoom: 3.0,
        maxZoom: 22.0,
        onMapReady: () {
          setState(() => _isMapReady = true);
          _centerOnCurrentLocation();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _getBaseLayerUrl(),
          userAgentPackageName: 'com.example.new_magnetic_survey_app',
          maxNativeZoom: 19,
        ),
        
        // Grid overlay
        if (_showGrid && _gridCells.isNotEmpty)
          PolygonLayer(
            polygons: _gridCells.map((cell) => Polygon(
              points: cell.bounds, // Using correct property name
              color: _getCellColor(cell.status).withOpacity(0.3),
              borderStrokeWidth: 1.0,
              borderColor: _getCellColor(cell.status),
            )).toList(),
          ),

        // Collected points with magnetic field colors
        MarkerLayer(
          markers: _collectedPoints.asMap().entries.map((entry) {
            int index = entry.key;
            LatLng point = entry.value;
            
            // Get magnetic field value for this point
            double magneticValue = _totalField; // Use current reading for recent points
            if (index < _savedReadings.length) {
              magneticValue = _savedReadings[index].totalField;
            }
            
            Color pointColor = getMagneticFieldColor(magneticValue);
            
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
                          angle: (_heading! * math.pi / 180),
                          child: Icon(Icons.navigation, color: Colors.white, size: 12),
                        )
                      : Icon(Icons.my_location, color: Colors.white, size: 12),
                ),
              ),
            ],
          ),

        // Team members
        if (_showTeamMembers && _teamMembers.isNotEmpty)
          MarkerLayer(
            markers: _teamMembers
                .where((member) => member.currentPosition != null) // Using correct property
                .map((member) => Marker(
              point: member.currentPosition!,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: member.markerColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    member.name[0].toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )).toList(),
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
        
        // Magnetometer Status
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
                'Mag: ${_totalField.toStringAsFixed(1)}nT',
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
          // Title
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Magnetic Field (nT)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          
          // Color scale bar
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    Colors.blue[900]!,
                    Colors.cyan,
                    Colors.green,
                    Colors.yellow,
                    Colors.red[900]!,
                  ],
                  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      '${MIN_MAGNETIC_FIELD.toInt()}',
                      style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Text(
                      '${MAX_MAGNETIC_FIELD.toInt()}',
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
      left: 20, // Moved to left side
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
                  // Header with expand/collapse indicator
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
                        Icon(
                          Icons.analytics,
                          color: Colors.white,
                          size: 18,
                        ),
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
                  
                  // Expandable content
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
                              _buildStatItem('Field', '${_totalField.toStringAsFixed(1)}nT', Icons.sensors),
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
        // Manual Recording Button
        FloatingActionButton(
          heroTag: "manual_record",
          onPressed: _recordMagneticReading,
          backgroundColor: Colors.green,
          child: Icon(Icons.add_location, color: Colors.white),
          tooltip: 'Record Point',
        ),
        
        SizedBox(height: 12),
        
        // Auto Recording Toggle Button (ONLY auto collect button remaining)
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

  // ==================== HELPER METHODS ====================

  void _updateCoverageStats() {
    if (_gridCells.isNotEmpty) {
      _completedCells = _gridCells.where((cell) => cell.status == GridCellStatus.completed).length;
      _coveragePercentage = (_completedCells / _gridCells.length) * 100;
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

  LatLng _getInitialMapCenter() {
    // Priority 1: Use current GPS position if available and reliable
    if (_currentPosition != null && _currentPosition!.accuracy < 100) {
      print('Using current GPS position as initial center');
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    
    // Priority 2: Use grid center (where the survey was created)
    if (widget.gridCenter != null) {
      print('Using grid center as initial center');
      return widget.gridCenter!;
    }
    
    // Priority 3: Try to detect approximate region from system timezone
    try {
      final timeZone = DateTime.now().timeZoneOffset;
      final offsetHours = timeZone.inHours;
      
      // Rough timezone to longitude mapping (very approximate)
      double approximateLongitude = offsetHours * 15.0; // 15 degrees per hour
      
      // Use equator as latitude fallback with timezone-based longitude
      print('Using timezone-based fallback center');
      return LatLng(0.0, approximateLongitude.clamp(-180.0, 180.0));
    } catch (e) {
      print('Timezone detection failed: $e');
    }
    
    // Priority 4: Ultimate fallback - center of the world
    print('Using fallback center (0,0)');
    return LatLng(0.0, 0.0);
  }

  String _getBaseLayerUrl() {
    switch (_currentBaseLayer) {
      case MapBaseLayer.openStreetMap:
        return 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapBaseLayer.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapBaseLayer.emag2Magnetic:
        return 'https://maps.ngdc.noaa.gov/arcgis/rest/services/web_mercator/emag2_magnetic_anomaly/MapServer/tile/{z}/{y}/{x}';
    }
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
      // Calculate appropriate zoom level for the grid
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
    
    // Calculate grid extent
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
    
    // Calculate appropriate zoom based on grid size
    double latDiff = maxLat - minLat;
    double lngDiff = maxLng - minLng;
    double maxDiff = math.max(latDiff, lngDiff);
    
    // Zoom level based on grid extent (rough approximation)
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
      for (var corner in cell.bounds) { // Fixed: use 'bounds' instead of 'corners'
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

  void _centerOnCurrentLocation() {
    if (_currentPosition != null && _isMapReady) {
      try {
        LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        _mapController.move(currentLocation, 16.0);
        print('Centered on current location: $currentLocation');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Centered on your current location'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        print('Error centering on current location: $e');
      }
    } else {
      print('Cannot center - Position: ${_currentPosition != null}, Map ready: $_isMapReady');
    }
  }

  void _waitForLocationAndCenter() {
    // Set up a timer to check for location updates
    Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_currentPosition != null && _isMapReady) {
        timer.cancel();
        print('GPS acquired - centering on location');
        _centerOnCurrentLocation();
        setState(() {
          _followLocation = true;
        });
      } else if (timer.tick > 20) { // 10 seconds timeout
        timer.cancel();
        print('Timeout waiting for GPS location');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Unable to get GPS location. Check permissions and GPS settings.'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                if (_currentPosition != null) {
                  _centerOnCurrentLocation();
                }
              },
            ),
          ),
        );
      }
    });
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
      _currentCell = nextCell;
    });

    print('Next target cell: ${nextCell?.id ?? "none"}');
  }

  // Helper method to calculate distance between two points (in meters)
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    double lat1Rad = point1.latitude * math.pi / 180;
    double lat2Rad = point2.latitude * math.pi / 180;
    double deltaLatRad = (point2.latitude - point1.latitude) * math.pi / 180;
    double deltaLngRad = (point2.longitude - point1.longitude) * math.pi / 180;

    double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLngRad / 2) * math.sin(deltaLngRad / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
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

  // ==================== SETTINGS (NOW INCLUDES TEAMS) ====================

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Settings & Teams'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Survey Settings Section
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
              
              // Team Settings Section
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
              
              // Calibration Section
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

  // ==================== TEAM FUNCTIONALITY ====================

  void _initializeTeamMode() {
    _teamService = TeamSyncService.instance; // Use singleton instance
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
    // Implementation for adding team members would go here
    // This could involve QR codes, sharing session IDs, etc.
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
              Navigator.pop(context); // Close team panel
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

  // ==================== EXPORT ====================

  void _exportSurveyData() {
    // Show export format selection dialog
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
              
              // Export format buttons
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
    Navigator.pop(context); // Close format selection dialog
    
    try {
      // Show loading dialog
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

      // Get all readings (combine collected and saved)
      List<MagneticReading> allReadings = List.from(_savedReadings);
      
      // Convert collected points to readings if needed
      for (int i = 0; i < _collectedPoints.length; i++) {
        final point = _collectedPoints[i];
        // Check if this point is already in saved readings
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

      // Export using ExportService with selected format
      String exportData = await ExportService.instance.exportProject(
        project: project,
        readings: allReadings,
        gridCells: _gridCells,
        fieldNotes: [], // Empty field notes for now
        format: format,
      );

      // Close loading dialog
      Navigator.pop(context);

      // Generate filename
      String extension = ExportService.instance.getFileExtension(format);
      String sanitizedProjectName = project.name
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^\w\-_]'), '');
      String filename = '${sanitizedProjectName}_${DateTime.now().millisecondsSinceEpoch}$extension';
      
      // Save and share with correct method name
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
            onPressed: () {
              // Additional share options could be added here
            },
          ),
        ),
      );
    } catch (e) {
      // Close loading dialog if still open
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