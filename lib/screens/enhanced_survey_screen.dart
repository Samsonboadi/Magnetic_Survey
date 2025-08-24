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
import '../services/database_service.dart';
import '../services/sensor_service.dart';
import '../services/grid_service.dart';
//import '../widgets/coverage_overlay.dart';
import '../widgets/field_notes_dialog.dart';

class EnhancedSurveyScreen extends StatefulWidget {
  final SurveyProject? project;
  
  EnhancedSurveyScreen({this.project});

  @override
  _EnhancedSurveyScreenState createState() => _EnhancedSurveyScreenState();
}

class _EnhancedSurveyScreenState extends State<EnhancedSurveyScreen> {
  MapController _mapController = MapController();
  Position? _currentPosition;
  double? _heading;
  MagneticReading? _lastReading;
  bool _isCollecting = false;
  bool _isWebMode = kIsWeb;
  
  // Survey data
  List<LatLng> _collectedPoints = [];
  List<GridCell> _gridCells = [];
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
  bool _autoNavigate = true;
  String _surveyMode = 'manual'; // manual, auto, team

  @override
  void initState() {
    super.initState();
    _initializeSurvey();
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

  void _createSampleGrid() {
    // Create a sample survey grid (4x4 grid)
    List<GridCell> cells = [];
    LatLng center = _isWebMode 
        ? LatLng(5.6037, -0.1870) // Ghana coordinates for web demo
        : LatLng(40.7589, -73.9851); // Default coordinates
    
    double spacing = 0.001; // Approximately 100m
    
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
    // Simulate GPS and sensor data for web demo
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
      setState(() {
        _currentPosition = position;
      });
      
      // Center map on current position
      _mapController.move(LatLng(position.latitude, position.longitude), 18.0);

      // Listen to position updates
      Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1, // Update every meter
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
    
    // Check which grid cell we're in
    _updateCurrentCell();
    
    // Auto-collect if in auto mode
    if (_isCollecting && _surveyMode == 'auto') {
      _recordMagneticReading();
    }
  }

  void _updateCurrentCell() {
    if (_currentPosition == null) return;
    
    LatLng currentPos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    
    for (GridCell cell in _gridCells) {
      if (_isPointInCell(currentPos, cell)) {
        if (_currentCell?.id != cell.id) {
          setState(() {
            // Mark previous cell as completed if it was in progress
            if (_currentCell != null && _currentCell!.status == GridCellStatus.inProgress) {
              _currentCell!.status = GridCellStatus.completed;
              _completedCells++;
            }
            
            // Set new current cell to in progress
            _currentCell = cell;
            if (cell.status == GridCellStatus.notStarted) {
              cell.status = GridCellStatus.inProgress;
            }
            
            // Find next target cell
            _findNextTargetCell();
            _updateCoverageStats();
          });
        }
        break;
      }
    }
  }

  bool _isPointInCell(LatLng point, GridCell cell) {
    // Simple bounding box check
    List<LatLng> bounds = cell.bounds;
    double minLat = bounds.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = bounds.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLon = bounds.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLon = bounds.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    
    return point.latitude >= minLat && point.latitude <= maxLat &&
           point.longitude >= minLon && point.longitude <= maxLon;
  }

  void _findNextTargetCell() {
    GridCell? nextCell = _gridCells.firstWhere(
      (cell) => cell.status == GridCellStatus.notStarted,
      orElse: () => _gridCells.first, // Fallback
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

  void _startSensorListening() {
    // Listen to magnetometer
    magnetometerEvents.listen((MagnetometerEvent event) {
      setState(() {
        _magneticX = event.x;
        _magneticY = event.y;
        _magneticZ = event.z;
        _totalField = SensorService.calculateTotalField(event.x, event.y, event.z);
      });
    });

    // Listen to compass
    FlutterCompass.events?.listen((CompassEvent event) {
      setState(() {
        _heading = event.heading;
      });
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
    // Collect data every 2 seconds while walking
    Future.doWhile(() async {
      if (!_isCollecting) return false;
      
      await Future.delayed(Duration(seconds: 2));
      if (_isCollecting) {
        await _recordMagneticReading();
      }
      return _isCollecting;
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
      _lastReading = reading;
      _collectedPoints.add(LatLng(reading.latitude, reading.longitude));
      _pointCount++;
      
      // Simulate minor variations for web demo
      if (_isWebMode) {
        _magneticX += (0.5 - 1.0) * 2;
        _magneticY += (0.5 - 1.0) * 2;
        _magneticZ += (0.5 - 1.0) * 2;
        _totalField = SensorService.calculateTotalField(_magneticX, _magneticY, _magneticZ);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
            icon: Icon(Icons.note_add),
            onPressed: _showFieldNotesDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(),
          
          // Map view
          Expanded(
            flex: 3,
            child: _buildMapView(),
          ),
          
          // Control panel
          _buildControlPanel(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "record",
            onPressed: _recordMagneticReading,
            child: Icon(Icons.add_location),
            backgroundColor: Colors.green,
          ),
          SizedBox(height: 10),
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
      padding: EdgeInsets.all(12),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatusItem('Coverage', '${_coveragePercentage.toStringAsFixed(0)}%', 
              _coveragePercentage > 75 ? Colors.green : _coveragePercentage > 25 ? Colors.orange : Colors.red),
          _buildStatusItem('Points', '$_pointCount', Colors.blue),
          _buildStatusItem('Field', '${_totalField.toStringAsFixed(0)} μT', Colors.purple),
          _buildStatusItem('Mode', _surveyMode.toUpperCase(), 
              _isCollecting ? Colors.green : Colors.grey),
        ],
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
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        center: _currentPosition != null 
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : LatLng(5.6037, -0.1870),
        zoom: 18.0,
        maxZoom: 20.0,
        minZoom: 10.0,
      ),
      children: [
        // Base map
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: ['a', 'b', 'c'],
        ),
        
        // Grid overlay
        if (_showGrid)
          PolygonLayer(
            polygons: _gridCells.map((cell) => Polygon(
              points: cell.bounds,
              color: _getCellColor(cell.status).withOpacity(0.3),
              borderColor: _getCellColor(cell.status),
              borderStrokeWidth: 2.0,
            )).toList(),
          ),
        
        // Collected points
        CircleLayer(
          circles: _collectedPoints.map((point) => CircleMarker(
            point: point,
            radius: 4,
            color: Colors.green,
            borderColor: Colors.white,
            borderStrokeWidth: 1,
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
                  angle: (_heading ?? 0) * 3.14159 / 180,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(Icons.navigation, color: Colors.white, size: 16),
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
                child:  Container(
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(Icons.flag, color: Colors.white, size: 20),
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
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Current cell info
          if (_currentCell != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getCellColor(_currentCell!.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getCellColor(_currentCell!.status)),
              ),
              child: Row(
                children: [
                  Icon(_getCellIcon(_currentCell!.status), 
                       color: _getCellColor(_currentCell!.status)),
                  SizedBox(width: 8),
                  Text(
                    'Current Cell: ${_currentCell!.id} (${_currentCell!.status.toString().split('.').last})',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          
          SizedBox(height: 12),
          
          // Navigation help
          if (_nextTargetCell != null && _autoNavigate)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.navigation, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Next Target: Cell ${_nextTargetCell!.id}'),
                  Spacer(),
                  if (_currentPosition != null)
                    Text(
                      '${_calculateDistance(_currentPosition!, LatLng(_nextTargetCell!.centerLat, _nextTargetCell!.centerLon)).toStringAsFixed(0)}m',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                ],
              ),
            ),
          
          SizedBox(height: 12),
          
          // Survey controls
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showGrid ? null : () => setState(() => _showGrid = true),
                  icon: Icon(Icons.grid_on),
                  label: Text('Show Grid'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _showGrid ? Colors.green : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _autoNavigate = !_autoNavigate),
                  icon: Icon(Icons.assistant_navigation),
                  label: Text(_autoNavigate ? 'Auto Nav' : 'Manual'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _autoNavigate ? Colors.blue : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
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
    return Geolocator.distanceBetween(from.latitude, from.longitude, to.latitude, to.longitude);
  }

  void _showFieldNotesDialog() {
    showDialog(
      context: context,
      builder: (context) => FieldNotesDialog(
        onNoteSaved: (note) {
          // Handle field note saving
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Field note saved: ${note.substring(0, 20)}...')),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}