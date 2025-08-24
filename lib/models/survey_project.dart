class SurveyProject {
  final int? id;
  final String name;
  final String description;
  final DateTime createdAt;
  final double? gridSpacing;
  final String? gridBounds;

  SurveyProject({
    this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    this.gridSpacing,
    this.gridBounds,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'gridSpacing': gridSpacing,
      'gridBounds': gridBounds,
    };
  }

  factory SurveyProject.fromMap(Map<String, dynamic> map) {
    return SurveyProject(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      createdAt: DateTime.parse(map['createdAt']),
      gridSpacing: map['gridSpacing'],
      gridBounds: map['gridBounds'],
    );
  }
}