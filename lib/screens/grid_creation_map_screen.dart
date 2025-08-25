// lib/screens/grid_creation_map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:math' as math;

import '../models/grid_cell.dart';
import '../services/grid_service.dart';

class GridCreationMapScreen extends StatefulWidget {
  @override
  _GridCreationMapScreenState createState() => _GridCreationMapScreenState();
}

class _GridCreationMapScreenState extends State<GridCreationMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _gridNameController = TextEditingController();
  final TextEditingController _spacingController = TextEditingController(text: '10');
  final TextEditingController _rowsController = TextEditingController(text: '7');
  final TextEditingController _colsController = TextEditingController(text: '7');
  
  Position? _currentPosition;
  LatLng? _gridCenter;
  List<GridCell> _previewGrid = [];
  List<LatLng> _boundaryPoints = [];
  bool _isDefiningBoundary = false;
  bool _showGridPreview = false;
  String _creationMode = 'center'; // 'center' or 'boundary'

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _gridNameController.text = 'Custom Grid ${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _gridNameController.dispose();
    _spacingController.dispose();
    _rowsController.dispose();
    _colsController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    if (kIsWeb) {
      // For web, use a default location (London)
      setState(() {
        _currentPosition = Position(
          latitude: 51.5074,
          longitude: -0.1278,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
        _gridCenter = LatLng(51.5074, -0.1278);
      });
      return;
    }

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _gridCenter = LatLng(position.latitude, position.longitude);
          });
          
          // Center the map on current location
          _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
        }
      }
    } catch (e) {
      print('Location error: $e');
      // Fallback to default location
      setState(() {
        _currentPosition = Position(
          latitude: 51.5074,
          longitude: -0.1278,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
        _gridCenter = LatLng(51.5074, -0.1278);
      });
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_creationMode == 'center') {
      setState(() {
        _gridCenter = point;
      });
      _generateGridPreview();
    } else if (_creationMode == 'boundary' && _isDefiningBoundary) {
      setState(() {
        _boundaryPoints.add(point);
      });
      
      if (_boundaryPoints.length >= 3) {
        _generateBoundaryGrid();
      }
    }
  }

  void _generateGridPreview() {
    if (_gridCenter == null) return;
    
    final spacing = double.tryParse(_spacingController.text) ?? 10.0;
    final rows = int.tryParse(_rowsController.text) ?? 7;
    final cols = int.tryParse(_colsController.text) ?? 7;
    
    // Convert meters to approximate degrees (rough approximation)
    final spacingDegrees = spacing / 111320.0; // meters to degrees
    
    final grid = GridService.createRegularGrid(
      center: _gridCenter!,
      spacing: spacingDegrees,
      rows: rows,
      cols: cols,
    );
    
    setState(() {
      _previewGrid = grid;
      _showGridPreview = true;
    });
  }

  void _generateBoundaryGrid() {
    // This is a simplified implementation
    // In a real app, you'd want more sophisticated boundary-based grid generation
    if (_boundaryPoints.length < 3) return;
    
    // Find the centroid of the boundary points
    double centerLat = _boundaryPoints.map((p) => p.latitude).reduce((a, b) => a + b) / _boundaryPoints.length;
    double centerLon = _boundaryPoints.map((p) => p.longitude).reduce((a, b) => a + b) / _boundaryPoints.length;
    
    setState(() {
      _gridCenter = LatLng(centerLat, centerLon);
    });
    
    _generateGridPreview();
  }

  void _resetGrid() {
    setState(() {
      _previewGrid = [];
      _boundaryPoints = [];
      _showGridPreview = false;
      _isDefiningBoundary = false;
    });
  }

  void _createGrid() {
    if (_previewGrid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please generate a grid preview first')),
      );
      return;
    }
    
    if (_gridNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a grid name')),
      );
      return;
    }
    
    // FIX: Include the grid center coordinates for proper storage
    final gridData = {
      'name': _gridNameController.text.trim(),
      'spacing': double.tryParse(_spacingController.text) ?? 10.0,
      'rows': int.tryParse(_rowsController.text) ?? 7,
      'cols': int.tryParse(_colsController.text) ?? 7,
      'center': _gridCenter,
      'points': _previewGrid.length,
      'cells': _previewGrid,
      'centerLat': _gridCenter?.latitude,  // ADD THIS
      'centerLon': _gridCenter?.longitude, // ADD THIS
    };
    
    Navigator.pop(context, gridData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Survey Grid'),
        backgroundColor: Colors.purple[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Control Panel
          _buildControlPanel(),
          
          // Map
          Expanded(
            child: _buildMap(),
          ),
          
          // Action Buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        children: [
          // Grid Name
          TextField(
            controller: _gridNameController,
            decoration: InputDecoration(
              labelText: 'Grid Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          
          SizedBox(height: 12),
          
          // Creation Mode Toggle
          Row(
            children: [
              Text('Creation Mode: ', style: TextStyle(fontWeight: FontWeight.w500)),
              Expanded(
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'center',
                      label: Text('Center Point'),
                      icon: Icon(Icons.center_focus_strong),
                    ),
                    ButtonSegment(
                      value: 'boundary',
                      label: Text('Boundary'),
                      icon: Icon(Icons.polyline),
                    ),
                  ],
                  selected: {_creationMode},
                  onSelectionChanged: (Set<String> selection) {
                    setState(() {
                      _creationMode = selection.first;
                      _resetGrid();
                    });
                  },
                ),
              ),
            ],
          ),
          
          SizedBox(height: 12),
          
          // Grid Parameters
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _spacingController,
                  decoration: InputDecoration(
                    labelText: 'Spacing (m)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _generateGridPreview(),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _rowsController,
                  decoration: InputDecoration(
                    labelText: 'Rows',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _generateGridPreview(),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _colsController,
                  decoration: InputDecoration(
                    labelText: 'Cols',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _generateGridPreview(),
                ),
              ),
            ],
          ),
          
          SizedBox(height: 8),
          
          // Instructions
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info, size: 16, color: Colors.blue[700]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _creationMode == 'center' 
                      ? 'Tap on the map to set the grid center point'
                      : _isDefiningBoundary
                        ? 'Tap to add boundary points (${_boundaryPoints.length}/3+ points)'
                        : 'Tap "Define Boundary" to start marking boundary points',
                    style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPosition != null 
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : LatLng(51.5074, -0.1278),
            initialZoom: 16.0,
            maxZoom: 20.0,
            minZoom: 10.0,
            onTap: _onMapTap,
          ),
          children: [
            // Base Map Layer
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.magnetic_survey_app',
            ),
            
            // Grid Preview
            if (_showGridPreview)
              PolygonLayer(
                polygons: _previewGrid.map((cell) => Polygon(
                  points: cell.bounds,
                  color: Colors.purple.withOpacity(0.2),
                  borderColor: Colors.purple,
                  borderStrokeWidth: 1.5,
                )).toList(),
              ),
            
            // Boundary Points
            if (_boundaryPoints.isNotEmpty)
              CircleLayer(
                circles: _boundaryPoints.asMap().entries.map((entry) => CircleMarker(
                  point: entry.value,
                  radius: 6,
                  color: Colors.red,
                  borderColor: Colors.white,
                  borderStrokeWidth: 2,
                )).toList(),
              ),
            
            // Boundary Lines
            if (_boundaryPoints.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [..._boundaryPoints, _boundaryPoints.first],
                    color: Colors.red,
                    strokeWidth: 2,
                  ),
                ],
              ),
            
            // Grid Center Point
            if (_gridCenter != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _gridCenter!,
                    radius: 8,
                    color: Colors.green,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            
            // Current Position
            if (_currentPosition != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    radius: 6,
                    color: Colors.blue,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
          ],
        ),
        
        // Map Info Overlay
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Grid Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                if (_showGridPreview) ...[
                  Text('Points: ${_previewGrid.length}', style: TextStyle(fontSize: 11)),
                  Text('Area: ${_calculateGridArea().toStringAsFixed(1)} m²', style: TextStyle(fontSize: 11)),
                ],
                if (_currentPosition != null)
                  Text('GPS: ±${_currentPosition!.accuracy.toStringAsFixed(1)}m', 
                       style: TextStyle(fontSize: 11, color: _currentPosition!.accuracy < 5 ? Colors.green : Colors.orange)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          if (_creationMode == 'boundary') ...[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isDefiningBoundary = !_isDefiningBoundary;
                    if (!_isDefiningBoundary) {
                      _boundaryPoints.clear();
                    }
                  });
                },
                icon: Icon(_isDefiningBoundary ? Icons.stop : Icons.polyline),
                label: Text(_isDefiningBoundary ? 'Stop Boundary' : 'Define Boundary'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDefiningBoundary ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            SizedBox(width: 8),
          ],
          
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _resetGrid,
              icon: Icon(Icons.refresh),
              label: Text('Reset'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          
          SizedBox(width: 8),
          
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _showGridPreview ? _createGrid : _generateGridPreview,
              icon: Icon(_showGridPreview ? Icons.check : Icons.grid_on),
              label: Text(_showGridPreview ? 'Create Grid' : 'Preview'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _showGridPreview ? Colors.green : Colors.purple[800],
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateGridArea() {
    if (_previewGrid.isEmpty) return 0.0;
    
    final spacing = double.tryParse(_spacingController.text) ?? 10.0;
    final rows = int.tryParse(_rowsController.text) ?? 7;
    final cols = int.tryParse(_colsController.text) ?? 7;
    
    return spacing * spacing * rows * cols;
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help, color: Colors.purple),
            SizedBox(width: 8),
            Text('Grid Creation Help'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Creation Modes:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Center Point: Tap on map to place grid center'),
              Text('• Boundary: Define irregular survey area boundaries'),
              SizedBox(height: 16),
              Text('Map Markers:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue)),
                SizedBox(width: 8),
                Text('Your current location'),
              ]),
              SizedBox(height: 4),
              Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
                SizedBox(width: 8),
                Text('Grid center point'),
              ]),
              SizedBox(height: 4),
              Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
                SizedBox(width: 8),
                Text('Boundary points'),
              ]),
              SizedBox(height: 16),
              Text('Tips:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Use satellite imagery for better context'),
              Text('• Consider terrain and accessibility'),
              Text('• Start with smaller grids for testing'),
              Text('• Grid spacing affects survey resolution'),
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
}