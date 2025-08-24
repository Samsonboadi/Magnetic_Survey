// lib/models/grid_cell.dart
import 'package:latlong2/latlong.dart';

enum GridCellStatus {
  notStarted,
  inProgress, 
  completed
}

class GridCell {
  final String id;
  final double centerLat;
  final double centerLon;
  final List<LatLng> bounds;
  GridCellStatus status;
  DateTime? startTime;
  DateTime? completedTime;
  int pointCount;
  String? notes;

  GridCell({
    required this.id,
    required this.centerLat,
    required this.centerLon,
    required this.bounds,
    this.status = GridCellStatus.notStarted,
    this.startTime,
    this.completedTime,
    this.pointCount = 0,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'centerLat': centerLat,
      'centerLon': centerLon,
      'bounds': bounds.map((point) => {'lat': point.latitude, 'lon': point.longitude}).toList(),
      'status': status.index,
      'startTime': startTime?.toIso8601String(),
      'completedTime': completedTime?.toIso8601String(),
      'pointCount': pointCount,
      'notes': notes,
    };
  }

  factory GridCell.fromMap(Map<String, dynamic> map) {
    List<LatLng> bounds = [];
    if (map['bounds'] != null) {
      bounds = (map['bounds'] as List).map((point) => 
        LatLng(point['lat'], point['lon'])
      ).toList();
    }

    return GridCell(
      id: map['id'],
      centerLat: map['centerLat'],
      centerLon: map['centerLon'],
      bounds: bounds,
      status: GridCellStatus.values[map['status'] ?? 0],
      startTime: map['startTime'] != null ? DateTime.parse(map['startTime']) : null,
      completedTime: map['completedTime'] != null ? DateTime.parse(map['completedTime']) : null,
      pointCount: map['pointCount'] ?? 0,
      notes: map['notes'],
    );
  }
}

