// lib/screens/survey_screen.dart - FIXED VERSION
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

  // Map orientation controls
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
  bool _followLocation = true;
  String _surveyMode = 'manual';
  MapBaseLayer _currentBaseLayer = MapBaseLayer.openStreetMap;

  // Data collection state tracking - BANNER FIXES
  bool _showDataBanner = false;
  Timer? _bannerHideTimer;

  // MAGNETOMETER CONTROL - NEW
  bool _isMagnetometerActive = false;

  // Grid boundary checking - NEW
  bool _isOutsideGrid = false;
  bool _wasCollectingBeforePause = false;

  // FIXED: Platform-specific magnetic field ranges
  static const double MIN_MAGNETIC_FIELD = 20.0;
  static const double MAX_MAGNETIC_FIELD = 70.0;

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

    // CRITICAL FIX: Properly initialize grid cells
    if (widget.initialGridCells != null && widget.initialGridCells!.isNotEmpty) {
      setState(() {
        _gridCells = List.from(widget.initialGridCells!); // Create a copy
        _showGrid = true; // Ensure grid is shown
      });
      print('Grid initialized with ${_gridCells.length} cells');
      _findNextTargetCell(); // Find first target cell
    }

    _initializeLocation();
    _startCompassOnly();
    _loadPreviousSurveyData();

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
            
            _checkGridBoundary();
            
            if (_followLocation && _isMapReady) {
              try {
                LatLng currentLocation = LatLng(position.latitude, position.longitude);
                _mapController.move(currentLocation, _mapController.camera.zoom);
              } catch (e) {
                print('Map controller not ready: $e');
              }
            }
          }
        });
      }
    } catch (e) {
      print('Location error: $e');
      _hasLocationError = true;
    }
  }

  void _startCompassOnly() {
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted && event.heading != null) {
        setState(() {
          _heading = event.heading;
        });
      }
    });
  }

  void _simulateDataForWeb() {
    _webSimulationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_isMagnetometerActive) {
          _magneticX = 25.0 + (math.Random().nextDouble() - 0.5) * 10;
          _magneticY = 15.0 + (math.Random().nextDouble() - 0.5) * 10;
          _magneticZ = 35.0 + (math.Random().nextDouble() - 0.5) * 10;
          _totalField = SensorService.calculateTotalField(_magneticX, _magneticY, _magneticZ);
        }
        _heading = (math.Random().nextDouble() * 360);
        _gpsAccuracy = 2.0 + math.Random().nextDouble() * 3;
      });
    });
  }

  // MAGNETOMETER CONTROL
  void _toggleMagnetometer() {
    setState(() {
      _isMagnetometerActive = !_isMagnetometerActive;
    });

    if (_isMagnetometerActive) {
      _startMagnetometerOnly();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Magnetometer readings started'),
          backgroundColor: Colors.purple,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _stopMagnetometerOnly();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Magnetometer readings stopped'),
          backgroundColor: Colors.grey,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _startMagnetometerOnly() {
    _magnetometerSubscription?.cancel();
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      if (mounted && _isMagnetometerActive) {
        setState(() {
          _magneticX = event.x - _magneticCalibrationX;
          _magneticY = event.y - _magneticCalibrationY;
          _magneticZ = event.z - _magneticCalibrationZ;
          _totalField = SensorService.calculateTotalField(_magneticX, _magneticY, _magneticZ);
        });
      }
    });
  }

  void _stopMagnetometerOnly() {
    _magnetometerSubscription?.cancel();
    _magnetometerSubscription = null;
    
    setState(() {
      _magneticX = 0.0;
      _magneticY = 0.0;
      _magneticZ = 0.0;
      _totalField = 0.0;
    });
  }

  // GRID BOUNDARY CHECKING
  void _checkGridBoundary() {
    if (_gridCells.isEmpty || _currentPosition == null) return;
    
    LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    bool isInsideAnyCell = false;
    
    for (var cell in _gridCells) {
      if (_isPointInCell(currentLocation, cell)) {
        isInsideAnyCell = true;
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
    
    if (_isOutsideGrid != !isInsideAnyCell) {
      setState(() {
        _isOutsideGrid = !isInsideAnyCell;
      });
      
      if (_isOutsideGrid && _isCollecting) {
        _wasCollectingBeforePause = true;
        setState(() {
          _isCollecting = false;
          _showDataBanner = false;
        });
        _automaticCollectionTimer?.cancel();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Outside grid boundary - recording paused')),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      } else if (!_isOutsideGrid && _wasCollectingBeforePause && !_isCollecting) {
        _wasCollectingBeforePause = false;
        setState(() {
          _isCollecting = true;
        });
        _startAutomaticCollection();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Back in grid - recording resumed')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  bool _isPointInCell(LatLng point, GridCell cell) {
    if (cell.bounds.length < 3) return false;
    
    int intersections = 0;
    for (int i = 0; i < cell.bounds.length; i++) {
      int j = (i + 1) % cell.bounds.length;
      
      if (((cell.bounds[i].latitude > point.latitude) != (cell.bounds[j].latitude > point.latitude)) &&
          (point.longitude < (cell.bounds[j].longitude - cell.bounds[i].longitude) * 
           (point.latitude - cell.bounds[i].latitude) / 
           (cell.bounds[j].latitude - cell.bounds[i].latitude) + cell.bounds[i].longitude)) {
        intersections++;
      }
    }
    
    return (intersections % 2) == 1;
  }

  // RECORDING METHODS
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

    final reading = MagneticReading(
      projectId: widget.project?.id ?? 1,
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      altitude: _currentPosition!.altitude ?? 0.0,
      magneticX: _magneticX,
      magneticY: _magneticY,
      magneticZ: _magneticZ,
      totalField: _totalField,
      timestamp: DateTime.now(),
      accuracy: _currentPosition!.accuracy,
      heading: _heading,
      notes: _isCollecting ? 'Auto collection' : 'Manual collection',
    );

    if (!_isWebMode && widget.project != null) {
      DatabaseService.instance.insertMagneticReading(reading);
    }

    _savedReadings.add(reading);
    _collectedPoints.add(LatLng(reading.latitude, reading.longitude));
    
    setState(() {
      _pointCount = _savedReadings.length;
    });

    _updateCoverageStats();
    
    if (_isCollecting) {
      _showTemporaryDataBanner();
    }
  }

  // FIXED: Your complete method with banner fixes
  void _toggleAutomaticCollection() {
    setState(() {
      _isCollecting = !_isCollecting;
      // CRITICAL FIX: Clear banner immediately when stopping
      if (!_isCollecting) {
        _showDataBanner = false;
        _bannerHideTimer?.cancel();
      }
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
    if (!_isCollecting) return;
    
    setState(() {
      _showDataBanner = true;
    });
    
    _bannerHideTimer?.cancel();
    _bannerHideTimer = Timer(Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showDataBanner = false;
        });
      }
    });
  }

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

  // UI COMPONENTS
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildMinimalAppBar(),
      body: Stack(
        children: [
          _buildFullScreenMapView(),
          
          Positioned(
            top: 10,
            left: 10,
            child: _buildFloatingStatusWidgets(),
          ),
          
          Positioned(
            top: 80,
            right: 10,
            child: _buildLocationFollowButton(),
          ),
          
          Positioned(
            top: 10,
            right: 10,
            child: _buildMagneticScale(),
          ),
          
          _buildCollapsibleTaskBar(),
          
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
        minZoom: 3.0,
        onMapReady: () {
          setState(() {
            _isMapReady = true;
          });
        },
        onTap: _onMapTap,
      ),
      children: [
        _buildBaseMapLayer(),
        
        if (_showGrid && _gridCells.isNotEmpty)
          PolygonLayer(
            polygons: _gridCells.map((cell) => Polygon(
              points: cell.bounds,
              color: _getCellColor(cell.status).withOpacity(0.3),
              borderColor: _getCellColor(cell.status),
              borderStrokeWidth: 2.0,
            )).toList(),
          ),

        if (_collectedPoints.isNotEmpty)
          CircleLayer(
            circles: _collectedPoints.map((point) => CircleMarker(
              point: point,
              radius: 4,
              color: getMagneticFieldColor(_totalField),
              borderColor: Colors.white,
              borderStrokeWidth: 1,
            )).toList(),
          ),

        if (_currentPosition != null) ...[
          CircleLayer(
            circles: [
              CircleMarker(
                point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                radius: 12,
                color: Colors.blue.withOpacity(0.3),
                borderColor: Colors.blue,
                borderStrokeWidth: 2,
              ),
            ],
          ),
          if (_heading != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  child: Transform.rotate(
                    angle: (_heading ?? 0) * math.pi / 180,
                    child: Icon(
                      Icons.navigation,
                      color: Colors.blue,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _buildFloatingActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: "magnetometer_toggle",
          onPressed: _toggleMagnetometer,
          backgroundColor: _isMagnetometerActive ? Colors.purple : Colors.grey,
          child: Icon(
            _isMagnetometerActive ? Icons.sensors : Icons.sensors_off,
            color: Colors.white,
            size: 20,
          ),
          tooltip: _isMagnetometerActive ? 'Stop Mag Reading' : 'Start Mag Reading',
        ),
        
        SizedBox(height: 12),
        
        FloatingActionButton(
          heroTag: "manual_record",
          onPressed: _recordMagneticReading,
          backgroundColor: Colors.green,
          child: Icon(Icons.add_location, color: Colors.white),
          tooltip: 'Record Point',
        ),
        
        SizedBox(height: 12),
        
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
        );
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

  Widget _buildLocationFollowButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _followLocation = !_followLocation;
        });
        
        if (_followLocation && _currentPosition != null && _isMapReady) {
          try {
            LatLng currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
            _mapController.move(currentLocation, _mapController.camera.zoom);
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
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (_isGpsCalibrated && _gpsAccuracy <= 10.0) 
                ? Colors.green.withOpacity(0.9) 
                : Colors.orange.withOpacity(0.9),
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
                (_isGpsCalibrated && _gpsAccuracy <= 10.0) ? Icons.gps_fixed : Icons.gps_not_fixed,
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
        
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isMagnetometerActive 
                ? Colors.purple.withOpacity(0.9) 
                : Colors.grey.withOpacity(0.9),
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
                _isMagnetometerActive ? Icons.sensors : Icons.sensors_off,
                size: 18,
                color: Colors.white,
              ),
              SizedBox(width: 6),
              Text(
                '${_totalField.toStringAsFixed(1)}μT',
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
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Mag:', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
          SizedBox(width: 4),
          Container(
            width: 60,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.blue[900]!,
                  Colors.cyan,
                  Colors.green,
                  Colors.yellow,
                  Colors.red,
                ],
              ),
            ),
          ),
          SizedBox(width: 4),
          Text('${MIN_MAGNETIC_FIELD.toInt()}-${MAX_MAGNETIC_FIELD.toInt()}μT', 
               style: TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  Widget _buildCollapsibleTaskBar() {
    return AnimatedBuilder(
      animation: _taskBarAnimation,
      builder: (context, child) {
        return Positioned(
          bottom: _taskBarAnimation.value * -120,
          left: 0,
          right: 0,
          child: Container(
            margin: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 4),
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
                    padding: EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Survey Stats',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          _isTaskBarCollapsed 
                              ? Icons.keyboard_arrow_up 
                              : Icons.keyboard_arrow_down,
                          color: Colors.blue[800],
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
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatItem('Points', _pointCount.toString(), Icons.location_on),
                            _buildStatItem('Coverage', '${_coveragePercentage.toStringAsFixed(1)}%', Icons.grid_on),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatItem('Field', '${_totalField.toStringAsFixed(1)}μT', Icons.sensors),
                            _buildStatItem('Accuracy', '±${_gpsAccuracy.toStringAsFixed(1)}m', Icons.gps_fixed),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
    int actualPointCount = _savedReadings.length;
    
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
              'Point recorded! Total: $actualPointCount readings',
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

  // HELPER METHODS
  LatLng _getInitialMapCenter() {
    if (widget.gridCenter != null) {
      return widget.gridCenter!;
    }
    
    if (_currentPosition != null && _currentPosition!.accuracy < 100) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    
    return LatLng(0.0, 0.0);
  }

  // POINT INFO POPUPS
  void _showPointInfo(LatLng point, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Survey Point ${index + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📍 Location', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Lat: ${point.latitude.toStringAsFixed(6)}°'),
            Text('Lon: ${point.longitude.toStringAsFixed(6)}°'),
            SizedBox(height: 12),
            Text('🧲 Magnetic Data', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Total Field: ${_totalField.toStringAsFixed(1)} μT'),
            Text('X: ${_magneticX.toStringAsFixed(1)} μT'),
            Text('Y: ${_magneticY.toStringAsFixed(1)} μT'),
            Text('Z: ${_magneticZ.toStringAsFixed(1)} μT'),
            SizedBox(height: 12),
            Text('⏰ Collection Time', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${DateTime.now().toString().split('.')[0]}'),
            SizedBox(height: 12),
            Text('🎯 GPS Info', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Accuracy: ±${_gpsAccuracy.toStringAsFixed(1)}m'),
            if (_heading != null)
              Text('Heading: ${_heading!.toStringAsFixed(1)}°'),
          ],
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

  void _showReadingInfo(MagneticReading reading, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reading ${index + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📍 Location', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Lat: ${reading.latitude.toStringAsFixed(6)}°'),
            Text('Lon: ${reading.longitude.toStringAsFixed(6)}°'),
            Text('Alt: ${reading.altitude.toStringAsFixed(1)}m'),
            SizedBox(height: 12),
            Text('🧲 Magnetic Data', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Total Field: ${reading.totalField.toStringAsFixed(1)} μT'),
            Text('X: ${reading.magneticX.toStringAsFixed(1)} μT'),
            Text('Y: ${reading.magneticY.toStringAsFixed(1)} μT'),
            Text('Z: ${reading.magneticZ.toStringAsFixed(1)} μT'),
            SizedBox(height: 12),
            Text('⏰ Recorded', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${reading.timestamp.toString().split('.')[0]}'),
            SizedBox(height: 12),
            Text('🎯 GPS Quality', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Accuracy: ±${reading.accuracy.toStringAsFixed(1)}m'),
            if (reading.heading != null)
              Text('Heading: ${reading.heading!.toStringAsFixed(1)}°'),
            if (reading.notes != null && reading.notes!.isNotEmpty) ...[
              SizedBox(height: 12),
              Text('📝 Notes', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${reading.notes}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          if (!_isWebMode)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteReading(reading, index);
              },
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  void _deleteReading(MagneticReading reading, int index) async {
    try {
      if (!_isWebMode && reading.projectId != null) {
        // Remove from database if it exists
        // Note: You'll need to implement deleteReading in DatabaseService
      }
      
      setState(() {
        _savedReadings.removeAt(index);
        _collectedPoints.removeWhere((point) => 
          (point.latitude - reading.latitude).abs() < 0.000001 &&
          (point.longitude - reading.longitude).abs() < 0.000001
        );
        _pointCount = _savedReadings.length;
      });
      
      _updateCoverageStats();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reading deleted'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting reading: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color getMagneticFieldColor(double totalField) {
    double normalized = (totalField - MIN_MAGNETIC_FIELD) / (MAX_MAGNETIC_FIELD - MIN_MAGNETIC_FIELD);
    normalized = math.max(0.0, math.min(1.0, normalized));
    
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
      return Color.lerp(Colors.yellow, Colors.red, t)!;
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

  void _updateCoverageStats() {
    if (_gridCells.isNotEmpty) {
      _completedCells = _gridCells.where((cell) => cell.status == GridCellStatus.completed).length;
      _coveragePercentage = (_completedCells / _gridCells.length) * 100;
    } else {
      _completedCells = 0;
      _coveragePercentage = 0.0;
    }
  }

  Future<void> _loadPreviousSurveyData() async {
    if (_isWebMode) return; // Skip database operations in web mode
    
    // Only try to load if we have a valid project with an ID
    if (widget.project?.id == null) {
      print('No valid project ID - skipping database load');
      return;
    }
    
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
      // Don't crash - just continue without previous data
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_surveyMode == 'manual' && !_isCollecting) {
      _recordMagneticReading();
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

  // EXPORT FUNCTIONALITY
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Choose export format for your survey data:'),
                SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.info, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Data includes ${_pointCount} points and grid information',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                
                // CSV Export
                _buildExportFormatButton(
                  ExportFormat.csv, 
                  Icons.table_chart, 
                  Colors.green,
                  'CSV Spreadsheet',
                  'Compatible with Excel, Google Sheets'
                ),
                SizedBox(height: 8),
                
                // GeoJSON Export
                _buildExportFormatButton(
                  ExportFormat.geojson, 
                  Icons.map, 
                  Colors.blue,
                  'GeoJSON',
                  'GIS and web mapping compatible'
                ),
                SizedBox(height: 8),
                
                // KML Export
                _buildExportFormatButton(
                  ExportFormat.kml, 
                  Icons.public, 
                  Colors.orange,
                  'Google Earth KML',
                  'Compatible with Google Earth'
                ),
                SizedBox(height: 8),
                
                // SQLite Export (only on mobile)
                if (!kIsWeb) _buildExportFormatButton(
                  ExportFormat.sqlite, 
                  Icons.storage, 
                  Colors.purple,
                  'SQLite Database',
                  'Complete database backup'
                ),
                if (!kIsWeb) SizedBox(height: 8),
                
                // Shapefile Export
                _buildExportFormatButton(
                  ExportFormat.shapefile, 
                  Icons.layers, 
                  Colors.teal,
                  'Shapefile (WKT)',
                  'GIS shapefile format'
                ),
              ],
            ),
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

  Widget _buildExportFormatButton(ExportFormat format, IconData icon, Color color, 
                                   String title, String description) {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.pop(context);
          _performExport(format);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performExport(ExportFormat format) async {
    try {
      final project = widget.project ?? SurveyProject(
        id: 1,
        name: 'Survey Session',
        description: 'Mobile survey data',
        createdAt: DateTime.now(),
      );

      String exportData = await ExportService.instance.exportProject(
        project: project,
        readings: _savedReadings,
        gridCells: _gridCells,
        fieldNotes: [],
        format: format,
      );

      if (kIsWeb) {
        print('Web export: $exportData');
      } else {
        await Share.shareXFiles(
          [XFile.fromData(
            Uint8List.fromList(exportData.codeUnits),
            name: '${project.name}_${_getFormatExtension(format)}.${_getFormatExtension(format)}',
            mimeType: 'text/plain',
          )],
          text: 'Survey data exported from TerraMag Field',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export completed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  String _getFormatExtension(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv: return 'csv';
      case ExportFormat.geojson: return 'geojson';
      case ExportFormat.kml: return 'kml';
      case ExportFormat.sqlite: return 'db';
      case ExportFormat.shapefile: return 'wkt';
    }
  }

  // SETTINGS
  void _showSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Survey Settings'),
          content: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                            setDialogState(() => _currentBaseLayer = value);
                            setState(() => _currentBaseLayer = value);
                          }
                        },
                      ),
                    ),
                    
                    Divider(),
                    
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
                        ],
                        onChanged: (Duration? value) {
                          if (value != null) {
                            setDialogState(() => _magneticPullRate = value);
                            setState(() => _magneticPullRate = value);
                          }
                        },
                      ),
                    ),
                    
                    Divider(),
                    
                    SwitchListTile(
                      title: Text('Show Grid'),
                      subtitle: Text('Display survey grid overlay'),
                      value: _showGrid,
                      onChanged: (value) {
                        setDialogState(() => _showGrid = value);
                        setState(() => _showGrid = value);
                      },
                    ),
                    
                    SwitchListTile(
                      title: Text('Auto Navigate'),
                      subtitle: Text('Auto-center map on location'),
                      value: _autoNavigate,
                      onChanged: (value) {
                        setDialogState(() => _autoNavigate = value);
                        setState(() => _autoNavigate = value);
                      },
                    ),
                    
                    SwitchListTile(
                      title: Text('Follow Location'),
                      subtitle: Text('Keep map centered on GPS'),
                      value: _followLocation,
                      onChanged: (value) {
                        setDialogState(() => _followLocation = value);
                        setState(() => _followLocation = value);
                      },
                    ),
                    
                    SwitchListTile(
                      title: Text('Show Compass'),
                      subtitle: Text('Display compass overlay'),
                      value: _showCompass,
                      onChanged: (value) {
                        setDialogState(() => _showCompass = value);
                        setState(() => _showCompass = value);
                      },
                    ),
                    
                    SwitchListTile(
                      title: Text('Team Mode'),
                      subtitle: Text('Enable team collaboration'),
                      value: _isTeamMode,
                      onChanged: (value) {
                        setDialogState(() => _isTeamMode = value);
                        setState(() => _isTeamMode = value);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _calibrateMagnetic();
              },
              child: Text('Calibrate Sensors'),
            ),
          ],
        );
      },
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

    if (nextCell != null && _autoNavigate && _isMapReady) {
      try {
        _mapController.move(
          LatLng(nextCell.centerLat, nextCell.centerLon),
          _mapController.camera.zoom
        );
      } catch (e) {
        print('Error navigating to next cell: $e');
      }
    }
  }

}