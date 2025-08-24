import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

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
    _loadSampleGrids();
  }

  void _loadSampleGrids() {
    // Load sample grids for demonstration
    setState(() {
      _importedGrids = [
        GridFile(
          name: 'Sample Grid 1.kml',
          type: 'KML',
          size: '2.3 KB',
          points: 25,
          imported: DateTime.now().subtract(Duration(hours: 2)),
        ),
        GridFile(
          name: 'Exploration_Area.geojson',
          type: 'GeoJSON',
          size: '5.1 KB',
          points: 64,
          imported: DateTime.now().subtract(Duration(days: 1)),
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Grid Import'),
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
          // Import options
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Survey Grids',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Import existing survey grids or create new ones',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _importFromFile,
                        icon: Icon(Icons.file_upload),
                        label: Text('Import File'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple[800],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _createNewGrid,
                        icon: Icon(Icons.grid_on),
                        label: Text('Create Grid'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purple[800],
                          side: BorderSide(color: Colors.purple[800]!),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Supported formats
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Supported Formats',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildFormatChip('KML', Icons.map, Colors.green),
                    _buildFormatChip('KMZ', Icons.archive, Colors.green),
                    _buildFormatChip('GeoJSON', Icons.code, Colors.blue),
                    _buildFormatChip('CSV', Icons.table_chart, Colors.orange),
                    _buildFormatChip('Shapefile', Icons.layers, Colors.purple),
                  ],
                ),
              ],
            ),
          ),

          // Grid list
          Expanded(
            child: _importedGrids.isEmpty
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
            'No Grids Imported',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[600]),
          ),
          SizedBox(height: 8),
          Text(
            'Import a survey grid file or create a new one',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
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
                Text(
                  'Imported ${_formatDate(grid.imported)}',
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
        return Colors.blue;
      case 'CSV':
        return Colors.orange;
      case 'SHAPEFILE':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  void _importFromFile() async {
    if (kIsWeb) {
      // Show web limitation dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('File Import'),
          content: Text(
            'File import is available on mobile devices. In web mode, you can use the sample grids or create new ones.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

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
    
    setState(() {
      _importedGrids.insert(0, GridFile(
        name: fileName,
        type: extension,
        size: _formatFileSize(fileSize),
        points: 36, // Simulated point count
        imported: DateTime.now(),
      ));
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  void _createNewGrid() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Grid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
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
            Text(
              'You can also draw the grid directly on the map during survey',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
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
              _createGridFromParameters();
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

  void _createGridFromParameters() {
    setState(() {
      _importedGrids.insert(0, GridFile(
        name: 'Custom Grid ${_importedGrids.length + 1}.grid',
        type: 'CUSTOM',
        size: '1.2 KB',
        points: 49,
        imported: DateTime.now(),
      ));
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Custom grid created successfully!')),
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
        title: Text('Grid Preview'),
        content: Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.grid_on, size: 48, color: Colors.grey[600]),
                SizedBox(height: 8),
                Text('Grid Preview'),
                Text('${grid.points} points'),
                SizedBox(height: 8),
                Text(
                  'Map preview available in mobile app',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
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

  void _deleteGrid(GridFile grid) async {
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
            Icon(Icons.help, color: Colors.blue),
            SizedBox(width: 8),
            Text('Grid Import Help'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Supported File Formats:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• KML/KMZ: Google Earth files with survey boundaries'),
              Text('• GeoJSON: Standard geospatial data format'),
              Text('• CSV: Coordinate files with lat/lon columns'),
              Text('• Shapefile: ESRI shapefile format'),
              SizedBox(height: 16),
              Text('How to Use:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. Import your grid file using "Import File"'),
              Text('2. Preview the grid to verify coverage'),
              Text('3. Select "Use for Survey" to start collecting data'),
              Text('4. Or create custom grids with "Create Grid"'),
              SizedBox(height: 16),
              Text('Tips:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Grid files should contain survey boundaries'),
              Text('• Ensure coordinates are in WGS84 format'),
              Text('• Test with small areas first'),
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

  GridFile({
    required this.name,
    required this.type,
    required this.size,
    required this.points,
    required this.imported,
  });
}