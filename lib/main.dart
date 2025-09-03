// lib/main.dart (Updated with Landing Screen + Grid Management)
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/survey_screen.dart';
import 'screens/project_manager_screen.dart';
import 'screens/grid_import_screen.dart';
import 'screens/landing_screen.dart';
import 'models/survey_project.dart';
import 'services/database_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Only initialize database on mobile platforms
  if (!kIsWeb) {
    await DatabaseService.instance.initDatabase();
    
    // Request permissions
    await _requestPermissions();
  }
  
  runApp(MagneticSurveyApp());
}

Future<void> _requestPermissions() async {
  Map<Permission, PermissionStatus> permissions = await [
    Permission.location,
    Permission.locationWhenInUse,
    Permission.camera,
    Permission.storage,
    Permission.microphone,
  ].request();
  
  // Check if essential permissions are granted
  if (permissions[Permission.location] != PermissionStatus.granted &&
      permissions[Permission.locationWhenInUse] != PermissionStatus.granted) {
    print('Location permission is required for this app.');
  }
}

class MagneticSurveyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TerraMag Field',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
          elevation: 4,
        ),
      ),
      home: AppWrapper(), // Changed from HomeScreen() to AppWrapper()
      debugShowCheckedModeBanner: false,
    );
  }
}

// NEW: AppWrapper to handle Landing Screen
class AppWrapper extends StatefulWidget {
  @override
  _AppWrapperState createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  bool _showLanding = true;

  @override
  void initState() {
    super.initState();
    
    // Set status bar style for landing screen
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF1E3C72),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  void _continueToApp() {
    setState(() {
      _showLanding = false;
    });
    
    // Reset status bar style for main app
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_showLanding) {
      return LandingScreen(
        onContinue: _continueToApp,
      );
    } else {
      return HomeScreen(); // Your existing HomeScreen
    }
  }
}

// Your existing HomeScreen class (unchanged)
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
            // App logo/header
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.compass_calibration, size: 64, color: Colors.blue[800]),
                  SizedBox(height: 8),
                  Text(
                    'TerraMag Field',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  Text(
                    'Professional Magnetic Survey Collection',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 32),
            
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
            
            // Menu options
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(Icons.add_location, color: Colors.green, size: 32),
                title: Text('New Survey', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Start collecting magnetic field data'),
                trailing: Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SurveyScreen(
                        project: SurveyProject(
                          name: 'Quick Survey ${DateTime.now().day}/${DateTime.now().month}',
                          description: 'New magnetic survey',
                          createdAt: DateTime.now(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            SizedBox(height: 12),
            
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(Icons.folder, color: Colors.blue, size: 32),
                title: Text('Project Manager', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Manage existing survey projects'),
                trailing: Icon(Icons.arrow_forward_ios),
                onTap: () {
                  if (kIsWeb) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Project Manager requires mobile app')),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ProjectManagerScreen()),
                    );
                  }
                },
              ),
            ),
            
            SizedBox(height: 12),
            
            // Grid Management Card
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(Icons.grid_on, color: Colors.purple, size: 32),
                title: Text('Grid Management', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Create and import survey grids'),
                trailing: Icon(Icons.arrow_forward_ios),
                onTap: () => _importGrid(context),
              ),
            ),
            
            SizedBox(height: 12),
            
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(Icons.settings, color: Colors.grey[700], size: 32),
                title: Text('App Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Configure app preferences'),
                trailing: Icon(Icons.arrow_forward_ios),
                onTap: () {
                  _showAppSettings(context);
                },
              ),
            ),
            
            SizedBox(height: 32),
            
            // App info
            Text(
              'Version 1.0.0',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            Text(
              'Professional magnetic survey data collection',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Grid import method
  void _importGrid(BuildContext context) {
    if (kIsWeb) {
      // Enhanced web demo dialog with map creation option
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.grid_on, color: Colors.purple),
              SizedBox(width: 8),
              Text('Grid Management'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grid creation and import options:'),
              SizedBox(height: 12),
              
              // Create with Map option
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => GridImportScreen()),
                    );
                  },
                  icon: Icon(Icons.map),
                  label: Text('Create with Map'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              
              SizedBox(height: 8),
              
              // Import File option  
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => GridImportScreen()),
                    );
                  },
                  icon: Icon(Icons.upload_file),
                  label: Text('Import Grid File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              
              SizedBox(height: 16),
              
              Text('Supported formats:'),
              SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  Chip(label: Text('KML/KMZ'), backgroundColor: Colors.green[100]),
                  Chip(label: Text('GeoJSON'), backgroundColor: Colors.blue[100]),
                  Chip(label: Text('CSV'), backgroundColor: Colors.orange[100]),
                  Chip(label: Text('Shapefile'), backgroundColor: Colors.purple[100]),
                ],
              ),
              
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue[700], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enhanced grid creation with map visualization now available!',
                        style: TextStyle(
                          fontSize: 12, 
                          color: Colors.blue[700],
                        ),
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
              child: Text('Close'),
            ),
          ],
        ),
      );
    } else {
      // Navigate directly to grid import screen for mobile
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => GridImportScreen()),
      );
    }
  }

  void _showAppSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('App Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('About'),
              subtitle: Text('TerraMag Field v1.0'),
              onTap: () {
                Navigator.pop(context);
                _showAboutDialog(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.security),
              title: Text('Permissions'),
              subtitle: Text('Manage app permissions'),
              onTap: () {
                Navigator.pop(context);
                _showPermissionsDialog(context);
              },
            ),
            if (!kIsWeb)
              ListTile(
                leading: Icon(Icons.storage),
                title: Text('Data Storage'),
                subtitle: Text('Manage local data'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Data stored in app documents folder')),
                  );
                },
              ),
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

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('About TerraMag Field'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TerraMag Field v1.0', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Professional magnetic survey data collection app for field geophysics.'),
            SizedBox(height: 16),
            Text('Features:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• Real-time magnetic field measurement'),
            Text('• GPS coordinate tracking'),
            Text('• Team collaboration'),
            Text('• Visual survey grid creation'),
            Text('• Data export (CSV, GeoJSON, KML)'),
            Text('• Field notes with photos'),
            Text('• Compass and navigation'),
            SizedBox(height: 16),
            Text('Requires device with magnetometer and GPS.'),
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

  void _showPermissionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Required Permissions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This app requires the following permissions:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            _buildPermissionItem(Icons.location_on, 'Location', 'For GPS coordinates'),
            _buildPermissionItem(Icons.camera_alt, 'Camera', 'For field photos'),
            _buildPermissionItem(Icons.storage, 'Storage', 'For saving data'),
            _buildPermissionItem(Icons.mic, 'Microphone', 'For voice notes'),
            SizedBox(height: 12),
            Text('You can manage these in your device settings.', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          if (!kIsWeb)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: Text('Open Settings'),
            ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(IconData icon, String title, String description) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}