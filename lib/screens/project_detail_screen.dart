import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/survey_project.dart';
import '../models/survey_grid.dart';
import '../services/database_service.dart';
import '../services/grid_service.dart';
import 'package:latlong2/latlong.dart';
import 'grid_creation_map_screen.dart';
import 'survey_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final SurveyProject project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  bool _loading = true;
  List<SurveyGrid> _grids = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (!kIsWeb && widget.project.id != null) {
      final rows = await DatabaseService.instance.getGridsForProject(widget.project.id!);
      setState(() {
        _grids = rows.map((e) => SurveyGrid.fromMap(e)).toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _createGrid() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => GridCreationMapScreen()),
    );
    if (result != null && widget.project.id != null) {
      final grid = SurveyGrid(
        projectId: widget.project.id!,
        name: result['name'] ?? 'Grid ${DateTime.now().millisecondsSinceEpoch}',
        description: result['description'],
        createdAt: DateTime.now(),
        spacing: (result['spacing'] as num?)?.toDouble(),
        rows: result['rows'] as int?,
        cols: result['cols'] as int?,
        points: result['points'] as int?,
        centerLat: (result['centerLat'] as num?)?.toDouble(),
        centerLon: (result['centerLon'] as num?)?.toDouble(),
        boundaryPointsJson: result['boundaryPointsJson'] as String?,
      );
      await DatabaseService.instance.insertGrid(grid.toMap());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Grid "${grid.name}" created')),
        );
      }
    }
  }

  Future<void> _deleteGrid(SurveyGrid grid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Grid?'),
        content: Text('Remove grid "${grid.name}" from project?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && grid.id != null) {
      await DatabaseService.instance.deleteGrid(grid.id!);
      await _load();
    }
  }

  void _startSurvey(SurveyGrid grid) {
    // Prepare optional grid overlay for the survey screen
    List gridCells = [];
    LatLng? center;
    if (grid.centerLat != null && grid.centerLon != null) {
      center = LatLng(grid.centerLat!, grid.centerLon!);
    }
    if (center != null && grid.spacing != null && grid.rows != null && grid.cols != null) {
      // Convert spacing meters -> degrees approx (matches creation)
      final spacingDegrees = (grid.spacing ?? 10.0) / 111320.0;
      gridCells = GridService.createRegularGrid(
        center: center,
        spacing: spacingDegrees,
        rows: grid.rows!,
        cols: grid.cols!,
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyScreen(
          project: widget.project,
          // Survey screen will store gridId with readings if provided
          selectedGridId: grid.id,
          initialGridCells: gridCells.isNotEmpty ? List.from(gridCells) : null,
          gridCenter: center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGrid,
        icon: const Icon(Icons.grid_on),
        label: const Text('Create Grid'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _grids.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.grid_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      const Text('No grids yet. Tap "Create Grid".'),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _grids.length,
                  itemBuilder: (ctx, i) {
                    final g = _grids[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.grid_on),
                        title: Text(g.name),
                        subtitle: Text([
                          if (g.spacing != null) '${g.spacing} m',
                          if (g.rows != null && g.cols != null) '${g.rows}×${g.cols}',
                          if (g.points != null) '${g.points} points',
                        ].where((e) => e != null && e.isNotEmpty).join(' · ')),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'survey') _startSurvey(g);
                            if (v == 'delete') _deleteGrid(g);
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(value: 'survey', child: Text('Start Survey')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete Grid')),
                          ],
                        ),
                        onTap: () => _startSurvey(g),
                      ),
                    );
                  },
                ),
    );
  }
}
