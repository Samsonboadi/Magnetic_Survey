import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'screens/survey_screen.dart';
import 'screens/project_manager_screen.dart';
import 'screens/grid_import_screen.dart';
import 'services/database_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Only initialize database on mobile platforms
  if (!kIsWeb) {
    await DatabaseService.instance.initDatabase();
  }
  
  runApp(MagneticSurveyApp());
}

class MagneticSurveyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TerraMag Field',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TerraMag Field'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Web warning
            if (kIsWeb)
              Container(
                padding: EdgeInsets.all(16),
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange[800]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Web Preview Mode: GPS and magnetometer require a mobile device',
                        style: TextStyle(color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              ),
            
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(Icons.add_location, color: Colors.green),
                title: Text('New Survey'),
                subtitle: Text('Start collecting magnetic data'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SurveyScreen()),
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(Icons.folder, color: Colors.orange),
                title: Text('Manage Projects'),
                subtitle: Text('View and export collected data'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProjectManagerScreen()),
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(Icons.grid_on, color: Colors.purple),
                title: Text('Import Grid'),
                subtitle: Text('Load survey grid from file'),
                onTap: () => _importGrid(context),
              ),
            ),
            
            // Platform info
            SizedBox(height: 20),
            Text(
              kIsWeb ? 'Running on: Web Browser' : 'Running on: Mobile Device',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _importGrid(BuildContext context) {
    if (kIsWeb) {
      // Show web demo dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.grid_on, color: Colors.purple),
              SizedBox(width: 8),
              Text('Import Grid'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grid import supports these formats:'),
              SizedBox(height: 8),
              Text('• KML/KMZ files'),
              Text('• GeoJSON files'),
              Text('• CSV with coordinates'),
              Text('• Shapefile (.shp)'),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Demo Mode: File import is available on mobile devices. You can draw grids directly in the survey screen.',
                  style: TextStyle(color: Colors.blue[700], fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => GridImportScreen()),
                );
              },
              child: Text('View Grid Tools'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[800],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } else {
      // Navigate to grid import screen for mobile
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => GridImportScreen()),
      );
    }
  }
}