// lib/screens/grid_import_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'grid_creation_map_screen.dart';
import 'survey_screen.dart';
import '../models/grid_cell.dart';

class GridImportScreen extends StatefulWidget {
  @override
  _GridImportScreenState createState() => _GridImportScreenState();
}

class _GridImportScreenState extends State<GridImportScreen> {
  List<GridFile> _importedGrids = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedGrids();
  }

  // ==================== GRID PERSISTENCE ====================

  Future<void> _loadSavedGrids() async {
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final gridData = prefs.getString('saved_grids');
      
      if (gridData != null) {
        final List<dynamic> decoded = json.decode(gridData);
        if (mounted) {
          setState(() {
            _importedGrids = decoded.map((g) => GridFile.fromJson(g)).toList();
          });
        }
      }
    } catch (e) {
      print('Error loading grids: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load saved grids'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveGrids() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_importedGrids.map((g) => g.toJson()).toList());
      await prefs.setString('saved_grids', encoded);
    } catch (e) {
      print('Error saving grids: $e');
    }
  }

  // ==================== UI BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Grid Management'),
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
          _buildActionBar(),
          _buildSupportedFormatsInfo(),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _importedGrids.isEmpty
                    ? _buildEmptyState()
                    : _buildGridList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _importFromFile,
                  icon: Icon(Icons.upload_file),
                  label: Text('Import File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _createNewGridWithMap,
                  icon: Icon(Icons.map),
                  label: Text('Create with Map'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _createNewGridDialog,
                  icon: Icon(Icons.grid_on),
                  label: Text('Quick Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[800],
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

  Widget _buildSupportedFormatsInfo() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supported Formats:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[800])),
          SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              _buildFormatChip('KML', Icons.map, Colors.green),
              _buildFormatChip('GeoJSON', Icons.code, Colors.blue),
              _buildFormatChip('CSV', Icons.table_chart, Colors.orange),
              _buildFormatChip('CUSTOM', Icons.grid_on, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormatChip(String format, IconData icon, Color color) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(format),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.3)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.grid_off, size: 80, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'No Grids Created',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[600]),
          ),
          SizedBox(height: 8),
          Text(
            'Import a survey grid file or create a new one',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNewGridWithMap,
            icon: Icon(Icons.map),
            label: Text('Create Grid with Map'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[800],
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridList() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _importedGrids.length,
      itemBuilder: (context, index) {
        final grid = _importedGrids[index];
        return _buildGridCard(grid);
      },
    );
  }

  Widget _buildGridCard(GridFile grid) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getTypeColor(grid.type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _getTypeColor(grid.type)),
                  ),
                  child: Text(
                    grid.type,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getTypeColor(grid.type),
                    ),
                  ),
                ),
                Spacer(),
                PopupMenuButton<String>(
                  onSelected: (action) => _handleGridAction(action, grid),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'use', child: Row(children: [Icon(Icons.play_arrow, color: Colors.green), SizedBox(width: 8), Text('Use for Survey')])),
                    PopupMenuItem(value: 'preview', child: Row(children: [Icon(Icons.visibility, color: Colors.blue), SizedBox(width: 8), Text('Preview')])),
                    if (grid.type == 'MAP' || grid.type == 'CUSTOM')
                      PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, color: Colors.orange), SizedBox(width: 8), Text('Edit')])),
                    PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.download, color: Colors.purple), SizedBox(width: 8), Text('Export')])),
                    PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete')])),
                  ],
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              grid.name,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.grid_on, size: 16, color: Colors.grey[600]),
                SizedBox(width: 4),
                Text('${grid.points} points', style: TextStyle(color: Colors.grey[600])),
                if (grid.spacing != null) ...[
                  SizedBox(width: 16),
                  Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                  SizedBox(width: 4),
                  Text('${grid.spacing}m spacing', style: TextStyle(color: Colors.grey[600])),
                ],
              ],
            ),
            if (grid.rows != null && grid.cols != null)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.grid_3x3, size: 16, color: Colors.grey[600]),
                    SizedBox(width: 4),
                    Text('${grid.rows}×${grid.cols} grid', style: TextStyle(color: Colors.grey[600])),
                    Spacer(),
                    Text(
                      '${_formatDate(grid.imported)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'KML':
      case 'KMZ':
        return Colors.green;
      case 'GEOJSON':
        return Colors.blue;
      case 'CSV':
        return Colors.orange;
      case 'MAP':
        return Colors.teal;
      case 'CUSTOM':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  // ==================== GRID ACTIONS ====================

  void _handleGridAction(String action, GridFile grid) {
    switch (action) {
      case 'use':
        _useGridForSurvey(grid);
        break;
      case 'preview':
        _previewGrid(grid);
        break;
      case 'edit':
        _editGrid(grid);
        break;
      case 'export':
        _exportGrid(grid);
        break;
      case 'delete':
        _deleteGrid(grid);
        break;
    }
  }

  void _useGridForSurvey(GridFile grid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Use Grid for Survey'),
        content: Text('Start a new survey using "${grid.name}" as the survey grid?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              
              navigator.pop(); // Close dialog
              
              try {
                // Convert GridFile to actual GridCells for survey
                List<GridCell> surveyGrid = _convertToGridCells(grid);
                
                // Navigate to survey screen with the grid
                await navigator.pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => SurveyScreen(
                      initialGridCells: surveyGrid,
                      gridCenter: _calculateGridCenter(surveyGrid),
                    ),
                  ),
                );
                
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Grid "${grid.name}" loaded for survey'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to load grid: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text('Start Survey'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _previewGrid(GridFile grid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Grid Preview - ${grid.name}'),
        content: Container(
          width: 300,
          height: 250,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.grid_on, size: 48, color: _getTypeColor(grid.type)),
                        SizedBox(height: 8),
                        Text('Grid Preview', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('${grid.points} points'),
                        if (grid.spacing != null && grid.rows != null && grid.cols != null) ...[
                          Text('${grid.spacing}m spacing'),
                          Text('${grid.rows}×${grid.cols} grid'),
                        ],
                        SizedBox(height: 8),
                        Text(
                          'Full visualization available in survey mode',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.info, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Interactive preview available when starting survey',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
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
            child: Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _useGridForSurvey(grid);
            },
            child: Text('Use for Survey'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _editGrid(GridFile grid) {
    if (grid.type == 'MAP' || grid.type == 'CUSTOM') {
      final TextEditingController nameController = TextEditingController(text: grid.name);
      final TextEditingController spacingController = TextEditingController(text: grid.spacing?.toString() ?? '10');
      final TextEditingController rowsController = TextEditingController(text: grid.rows?.toString() ?? '7');
      final TextEditingController colsController = TextEditingController(text: grid.cols?.toString() ?? '7');

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Edit Grid'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Grid Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: spacingController,
                      decoration: InputDecoration(
                        labelText: 'Spacing (m)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: rowsController,
                      decoration: InputDecoration(
                        labelText: 'Rows',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: colsController,
                      decoration: InputDecoration(
                        labelText: 'Columns',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
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
              onPressed: () async {
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                
                final spacing = double.tryParse(spacingController.text) ?? 10.0;
                final rows = int.tryParse(rowsController.text) ?? 7;
                final cols = int.tryParse(colsController.text) ?? 7;
                final points = rows * cols;
                
                setState(() {
                  final index = _importedGrids.indexOf(grid);
                  _importedGrids[index] = GridFile(
                    name: nameController.text.trim(),
                    type: grid.type,
                    size: _estimateGridSize(points),
                    points: points,
                    spacing: spacing,
                    rows: rows,
                    cols: cols,
                    imported: grid.imported,
                  );
                });
                
                await _saveGrids();
                navigator.pop();
                
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Grid updated successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot edit imported grid files'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _exportGrid(GridFile grid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Export Grid'),
        content: Text('Choose export format for "${grid.name}":'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              
              navigator.pop();
              
              if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Grid exported as KML (demo)'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text('KML'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              
              navigator.pop();
              
              if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Grid exported as CSV (demo)'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text('CSV'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGrid(GridFile grid) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Grid'),
        content: Text('Are you sure you want to delete "${grid.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _importedGrids.remove(grid);
      });
      
      await _saveGrids();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Grid "${grid.name}" deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ==================== GRID CREATION ====================

  void _importFromFile() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File import feature will be implemented in future updates'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  void _createNewGridWithMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => GridCreationMapScreen(),
      ),
    );

    if (result != null) {
      final newGrid = GridFile(
        name: result['name'] ?? 'Custom Grid',
        type: 'MAP',
        size: _estimateGridSize(result['points'] ?? 0),
        points: result['points'] ?? 0,
        spacing: result['spacing'],
        rows: result['rows'],
        cols: result['cols'],
        imported: DateTime.now(),
      );

      setState(() {
        _importedGrids.insert(0, newGrid);
      });

      await _saveGrids();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Grid "${newGrid.name}" created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _createNewGridDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController spacingController = TextEditingController(text: '10');
    final TextEditingController linesController = TextEditingController(text: '7');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quick Create Grid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Grid Name',
                hintText: 'Enter grid name',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: spacingController,
                    decoration: InputDecoration(
                      labelText: 'Spacing (m)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: linesController,
                    decoration: InputDecoration(
                      labelText: 'Grid Size',
                      hintText: 'e.g., 7 for 7x7',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, size: 16, color: Colors.orange[700]),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'For precise positioning, use "Create with Map" instead',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
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
              final navigator = Navigator.of(context);
              navigator.pop();
              _createGridFromParameters(
                nameController.text,
                spacingController.text,
                linesController.text,
              );
            },
            child: Text('Create'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[800],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _createGridFromParameters(String name, String spacing, String lines) async {
    final gridName = name.trim().isEmpty ? 'Quick Grid ${_importedGrids.length + 1}' : name.trim();
    final spacingValue = double.tryParse(spacing) ?? 10.0;
    final linesValue = int.tryParse(lines) ?? 7;
    final gridPoints = linesValue * linesValue;
    
    final newGrid = GridFile(
      name: gridName,
      type: 'CUSTOM',
      size: _estimateGridSize(gridPoints),
      points: gridPoints,
      spacing: spacingValue,
      rows: linesValue,
      cols: linesValue,
      imported: DateTime.now(),
    );
    
    setState(() {
      _importedGrids.insert(0, newGrid);
    });
    
    await _saveGrids();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grid "$gridName" created with $gridPoints points!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ==================== HELPER METHODS ====================

  List<GridCell> _convertToGridCells(GridFile grid) {
    List<GridCell> cells = [];
    
    // Use default center location (can be improved with actual location)
    LatLng center = LatLng(5.6037, -0.1870); // Default fallback
    
    if (grid.rows != null && grid.cols != null && grid.spacing != null) {
      double cellSize = grid.spacing! / 111000; // Convert meters to degrees (rough approximation)
      int rows = grid.rows!;
      int cols = grid.cols!;
      double halfRows = rows / 2.0;
      double halfCols = cols / 2.0;
      
      for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
          double lat = center.latitude + (i - halfRows) * cellSize;
          double lon = center.longitude + (j - halfCols) * cellSize;
          
          List<LatLng> bounds = [
            LatLng(lat, lon),
            LatLng(lat + cellSize, lon),
            LatLng(lat + cellSize, lon + cellSize),
            LatLng(lat, lon + cellSize),
          ];
          
          GridCell cell = GridCell(
            id: 'cell_${i}_${j}',
            centerLat: lat + cellSize / 2,
            centerLon: lon + cellSize / 2,
            bounds: bounds,
            status: GridCellStatus.notStarted,
            pointCount: 0,
            notes: null,
          );
          cells.add(cell);
        }
      }
    }
    
    return cells;
  }

  LatLng _calculateGridCenter(List<GridCell> cells) {
    if (cells.isEmpty) return LatLng(5.6037, -0.1870);
    
    double totalLat = 0;
    double totalLon = 0;
    
    for (var cell in cells) {
      totalLat += cell.centerLat;
      totalLon += cell.centerLon;
    }
    
    return LatLng(totalLat / cells.length, totalLon / cells.length);
  }

  String _estimateGridSize(int points) {
    if (points < 10) return '< 1KB';
    if (points < 50) return '~ 2KB';
    if (points < 100) return '~ 5KB';
    if (points < 500) return '~ 20KB';
    return '~ ${(points * 0.05).toStringAsFixed(0)}KB';
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help, color: Colors.purple),
            SizedBox(width: 8),
            Text('Grid Management Help'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Creation Methods:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Create with Map: Visual grid creation with location context'),
              Text('• Import File: Load existing grid files (KML, GeoJSON, CSV, etc.)'),
              Text('• Quick Create: Simple parameter-based grid generation'),
              SizedBox(height: 16),
              Text('Supported File Formats:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• KML/KMZ: Google Earth files with survey boundaries'),
              Text('• GeoJSON: Standard geospatial data format'),
              Text('• CSV: Coordinate files with lat/lon columns'),
              Text('• Custom: App-generated grids'),
              SizedBox(height: 16),
              Text('Best Practices:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Use "Create with Map" for precise positioning'),
              Text('• Start with smaller grids for testing'),
              Text('• Consider terrain and site accessibility'),
              Text('• Ensure coordinates are in WGS84 format'),
              Text('• Test grids before field deployment'),
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

// ==================== GRID FILE MODEL ====================

class GridFile {
  final String name;
  final String type;
  final String size;
  final int points;
  final DateTime imported;
  final double? spacing;
  final int? rows;
  final int? cols;

  GridFile({
    required this.name,
    required this.type,
    required this.size,
    required this.points,
    required this.imported,
    this.spacing,
    this.rows,
    this.cols,
  });

  // JSON serialization for persistence
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'size': size,
      'points': points,
      'imported': imported.toIso8601String(),
      'spacing': spacing,
      'rows': rows,
      'cols': cols,
    };
  }

  static GridFile fromJson(Map<String, dynamic> json) {
    return GridFile(
      name: json['name'],
      type: json['type'],
      size: json['size'],
      points: json['points'],
      imported: DateTime.parse(json['imported']),
      spacing: json['spacing']?.toDouble(),
      rows: json['rows'],
      cols: json['cols'],
    );
  }

  // Create a copy with updated fields
  GridFile copyWith({
    String? name,
    String? type,
    String? size,
    int? points,
    DateTime? imported,
    double? spacing,
    int? rows,
    int? cols,
  }) {
    return GridFile(
      name: name ?? this.name,
      type: type ?? this.type,
      size: size ?? this.size,
      points: points ?? this.points,
      imported: imported ?? this.imported,
      spacing: spacing ?? this.spacing,
      rows: rows ?? this.rows,
      cols: cols ?? this.cols,
    );
  }

  @override
  String toString() {
    return 'GridFile(name: $name, type: $type, points: $points)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GridFile &&
        other.name == name &&
        other.type == type &&
        other.points == points &&
        other.imported == imported;
  }

  @override
  int get hashCode {
    return name.hashCode ^ 
           type.hashCode ^ 
           points.hashCode ^ 
           imported.hashCode;
  }
}