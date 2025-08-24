import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import '../models/survey_project.dart';
import '../models/magnetic_reading.dart';
import '../services/database_service.dart';
import 'survey_screen.dart';

class ProjectManagerScreen extends StatefulWidget {
  @override
  _ProjectManagerScreenState createState() => _ProjectManagerScreenState();
}

class _ProjectManagerScreenState extends State<ProjectManagerScreen> {
  List<SurveyProject> _projects = [];
  Map<int, int> _projectReadingCounts = {};
  bool _isLoading = true;
  String _newProjectName = '';
  String _newProjectDescription = '';

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  void _loadProjects() async {
    setState(() {
      _isLoading = true;
    });

    if (!kIsWeb) {
      // Load real projects from database
      final projects = await DatabaseService.instance.getAllProjects();
      Map<int, int> readingCounts = {};
      
      for (var project in projects) {
        if (project.id != null) {
          final count = await DatabaseService.instance.getReadingCountForProject(project.id!);
          readingCounts[project.id!] = count;
        }
      }
      
      setState(() {
        _projects = projects;
        _projectReadingCounts = readingCounts;
        _isLoading = false;
      });
    } else {
      // Create demo projects for web
      await Future.delayed(Duration(milliseconds: 500));
      setState(() {
        _projects = [
          SurveyProject(
            id: 1,
            name: 'Demo Survey 1',
            description: 'Sample magnetic survey project',
            createdAt: DateTime.now().subtract(Duration(days: 2)),
          ),
          SurveyProject(
            id: 2,
            name: 'Test Site Alpha',
            description: 'Northern exploration area',
            createdAt: DateTime.now().subtract(Duration(days: 5)),
          ),
        ];
        _projectReadingCounts = {1: 25, 2: 47};
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Project Manager'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadProjects,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading projects...'),
                ],
              ),
            )
          : _projects.isEmpty
              ? _buildEmptyState()
              : _buildProjectList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateProjectDialog,
        child: Icon(Icons.add),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'No Projects Yet',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[600]),
          ),
          SizedBox(height: 8),
          Text(
            'Create your first magnetic survey project',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreateProjectDialog,
            icon: Icon(Icons.add),
            label: Text('Create New Project'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectList() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _projects.length,
      itemBuilder: (context, index) {
        final project = _projects[index];
        final readingCount = _projectReadingCounts[project.id] ?? 0;
        
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.location_on, color: Colors.blue[800], size: 28),
            ),
            title: Text(
              project.name,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.description),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                    SizedBox(width: 4),
                    Text(
                      '${project.createdAt.day}/${project.createdAt.month}/${project.createdAt.year}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    SizedBox(width: 16),
                    Icon(Icons.my_location, size: 14, color: Colors.grey[600]),
                    SizedBox(width: 4),
                    Text(
                      '$readingCount points',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'open',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 18),
                      SizedBox(width: 8),
                      Text('Open Survey'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 18),
                      SizedBox(width: 8),
                      Text('Export Data'),
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
              onSelected: (value) => _handleProjectAction(value, project),
            ),
            onTap: () => _openProject(project),
          ),
        );
      },
    );
  }

  void _showCreateProjectDialog() {
    _newProjectName = '';
    _newProjectDescription = '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Project Name *',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _newProjectName = value,
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (value) => _newProjectDescription = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _saveNewProject,
            child: Text('Create'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _saveNewProject() async {
    if (_newProjectName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a project name')),
      );
      return;
    }

    final project = SurveyProject(
      name: _newProjectName.trim(),
      description: _newProjectDescription.trim(),
      createdAt: DateTime.now(),
    );

    if (!kIsWeb) {
      await DatabaseService.instance.insertProject(project);
    } else {
      // Add to demo list
      setState(() {
        _projects.insert(0, SurveyProject(
          id: _projects.length + 1,
          name: project.name,
          description: project.description,
          createdAt: project.createdAt,
        ));
      });
    }

    Navigator.pop(context);
    _loadProjects();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Project "${project.name}" created!')),
    );
  }

  void _openProject(SurveyProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SurveyScreen(project: project),
      ),
    );
  }

  void _handleProjectAction(String action, SurveyProject project) async {
    switch (action) {
      case 'open':
        _openProject(project);
        break;
      case 'export':
        await _exportProject(project);
        break;
      case 'delete':
        await _deleteProject(project);
        break;
    }
  }

  Future<void> _exportProject(SurveyProject project) async {
    try {
      if (kIsWeb) {
        // Demo export for web
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Demo: Export functionality available on mobile devices')),
        );
        return;
      }

      final csvData = await DatabaseService.instance.exportProjectToCSV(project.id!);
      
      // For now, just share the CSV data
      await Share.share(
        csvData,
        subject: 'Magnetic Survey Data - ${project.name}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data exported successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _deleteProject(SurveyProject project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Project'),
        content: Text('Are you sure you want to delete "${project.name}"?\n\nThis will permanently remove the project and all its magnetic readings.'),
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
      if (!kIsWeb && project.id != null) {
        await DatabaseService.instance.deleteProject(project.id!);
      } else {
        // Remove from demo list
        setState(() {
          _projects.removeWhere((p) => p.id == project.id);
        });
      }
      
      _loadProjects();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project "${project.name}" deleted')),
      );
    }
  }
}