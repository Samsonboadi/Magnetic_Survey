// lib/screens/grid_import_screen.dart (Updated with Map Integration)
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'grid_creation_map_screen.dart';

class GridImportScreen extends StatefulWidget {
  @override
  _GridImportScreenState createState() => _GridImportScreenState();
}

class _GridImportScreenState extends State<GridImportScreen> {
  List<GridFile> _importedGrids = [];
  bool _isLoading = false;

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
          // Top Action Bar
          Container(
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
          ),
          
          // Supported Formats Info
          Container(
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
                    _buildFormatChip('KMZ', Icons.archive, Colors.green),
                    _buildFormatChip('GeoJSON', Icons.code, Colors.blue),
                    _buildFormatChip('CSV', Icons.table_chart, Colors.orange),
                    _buildFormatChip('SHP', Icons.layers, Colors.purple),
                  ],
                ),
              ],
            ),
          ),
          
          // Grid List
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
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getTypeColor(grid.type),
              child: Text(
                grid.type.substring(0, 1),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(grid.name, style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${grid.points} grid points • ${grid.size}'),
                if (grid.spacing != null && grid.rows != null && grid.cols != null)
                  Text('${grid.spacing}m spacing • ${grid.rows}×${grid.cols} grid'),
                Text(
                  'Created ${_formatDate(grid.imported)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'use',
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow, size: 18),
                      SizedBox(width: 8),
                      Text('Use for Survey'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'preview',
                  child: Row(
                    children: [
                      Icon(Icons.visibility, size: 18),
                      SizedBox(width: 8),
                      Text('Preview'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 18),
                      SizedBox(width: 8),
                      Text('Export'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) => _handleGridAction(value, grid),
            ),
            onTap: () => _previewGrid(grid),
          ),
        );
      },
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toUpperCase()) {
      case 'KML':
      case 'KMZ':
        return Colors.green;
      case 'GEOJSON':
      case 'JSON':
        return Colors.blue;
      case 'CSV':
        return Colors.orange;
      case 'SHP':
        return Colors.purple;
      case 'MAP':
        return Colors.green[700]!;
      case 'CUSTOM':
      default:
        return Colors.grey[600]!;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  // Import from file functionality
  Future<void> _importFromFile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kml', 'kmz', 'geojson', 'json', 'csv', 'shp'],
        allowMultiple: true,
      );

      if (result != null) {
        for (PlatformFile file in result.files) {
          if (file.path != null) {
            await _processImportedFile(File(file.path!));
          }
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.files.length} file(s) imported successfully!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _processImportedFile(File file) async {
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();
    final extension = fileName.split('.').last.toUpperCase();
    
    // Simulate processing time
    await Future.delayed(Duration(milliseconds: 500));
    
    // Generate random but reasonable point count based on file size
    final pointCount = (fileSize / 1000).round().clamp(16, 144);
    
    setState(() {
      _importedGrids.insert(0, GridFile(
        name: fileName,
        type: extension,
        size: _formatFileSize(fileSize),
        points: pointCount,
        imported: DateTime.now(),
      ));
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  // Create new grid with map visualization
  void _createNewGridWithMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => GridCreationMapScreen(),
      ),
    );

    if (result != null) {
      setState(() {
        _importedGrids.insert(0, GridFile(
          name: result['name'],
          type: 'MAP',
          size: _estimateGridSize(result['points']),
          points: result['points'],
          spacing: result['spacing'],
          rows: result['rows'],
          cols: result['cols'],
          imported: DateTime.now(),
        ));
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grid "${result['name']}" created successfully!')),
      );
    }
  }

  String _estimateGridSize(int points) {
    // Rough estimate based on point count
    final estimatedBytes = points * 100; // 100 bytes per point estimate
    return _formatFileSize(estimatedBytes);
  }

  // Quick create dialog (simplified version without map)
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
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: linesController,
                    decoration: InputDecoration(
                      labelText: 'Lines',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(4),
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
              Navigator.pop(context);
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

  void _createGridFromParameters(String name, String spacing, String lines) {
    // Parse user inputs with validation
    final gridName = name.trim().isEmpty ? 'Quick Grid ${_importedGrids.length + 1}' : name.trim();
    final spacingValue = double.tryParse(spacing) ?? 10.0;
    final linesValue = int.tryParse(lines) ?? 7;
    
    // Calculate grid points based on user input (square grid)
    final gridPoints = linesValue * linesValue;
    
    setState(() {
      _importedGrids.insert(0, GridFile(
        name: gridName,
        type: 'CUSTOM',
        size: _estimateGridSize(gridPoints),
        points: gridPoints,
        spacing: spacingValue,
        rows: linesValue,
        cols: linesValue,
        imported: DateTime.now(),
      ));
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Grid "$gridName" created with $gridPoints points!')),
    );
  }

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
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Go back to main screen
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Grid "${grid.name}" loaded for survey')),
              );
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
                          'Interactive preview available in survey mode',
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
                      'Full grid visualization available when starting survey',
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
      // Allow editing of custom grids
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
                        labelText: 'Cols',
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
              onPressed: () {
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
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Grid updated successfully')),
                );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot edit imported grid files')),
      );
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
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Grid exported as KML (demo)')),
              );
            },
            child: Text('KML'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Grid exported as CSV (demo)')),
              );
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grid "${grid.name}" deleted')),
      );
    }
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
              Text('• Shapefile: ESRI shapefile format'),
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
}