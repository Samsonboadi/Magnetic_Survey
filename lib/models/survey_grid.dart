class SurveyGrid {
  final int? id;
  final int projectId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final double? spacing;
  final int? rows;
  final int? cols;
  final int? points;
  final double? centerLat;
  final double? centerLon;
  final String? boundaryPointsJson; // optional serialized boundary vertices

  SurveyGrid({
    this.id,
    required this.projectId,
    required this.name,
    this.description,
    required this.createdAt,
    this.spacing,
    this.rows,
    this.cols,
    this.points,
    this.centerLat,
    this.centerLon,
    this.boundaryPointsJson,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'projectId': projectId,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'spacing': spacing,
      'rows': rows,
      'cols': cols,
      'points': points,
      'centerLat': centerLat,
      'centerLon': centerLon,
      'boundaryPoints': boundaryPointsJson,
    };
  }

  factory SurveyGrid.fromMap(Map<String, dynamic> map) {
    return SurveyGrid(
      id: map['id'] as int?,
      projectId: (map['projectId'] as num).toInt(),
      name: map['name'] as String,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      spacing: (map['spacing'] as num?)?.toDouble(),
      rows: (map['rows'] as num?)?.toInt(),
      cols: (map['cols'] as num?)?.toInt(),
      points: (map['points'] as num?)?.toInt(),
      centerLat: (map['centerLat'] as num?)?.toDouble(),
      centerLon: (map['centerLon'] as num?)?.toDouble(),
      boundaryPointsJson: map['boundaryPoints'] as String?,
    );
  }
}

